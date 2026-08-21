-- supabase/tests/0065_webhook_payment_rpc_test.sql
-- 010 US1: record_webhook_payment upsert semantics, merchant_order_id stamping,
-- mark_payment_failed detail jsonb

begin;
select plan(8);

-- ---------------------------------------------------------------- fixtures
delete from public.payments where gateway_ref in ('txn65_hook', 'txn65_orphan') or merchant_order_id in ('651', '652');
delete from public.bookings where id in (951);
delete from public.service_slots where id in (951);
delete from public.services where id in (951);

insert into auth.users (id, email, phone) values
  ('cccccccc-0000-0000-0000-000000006501'::uuid, 'user6501@test.com', '+201000006501')
on conflict (id) do update set email = excluded.email, phone = excluded.phone;
insert into public.users (id, phone, name, role, tenant_id)
  values ('cccccccc-0000-0000-0000-000000006501'::uuid, '+201000006501', 'Owner', 'USER', 1)
on conflict (id) do update set role = 'USER';

insert into public.services (id, tenant_id, title_ar)
  overriding system value values (951, 1, 'قداس');
insert into public.service_slots (id, service_id, tenant_id, starts_at, ends_at, capacity)
  overriding system value values (951, 951, 1, now() + interval '3 days', now() + interval '3 days 2 hours', 5);
insert into public.bookings (id, user_id, slot_id, tenant_id, status)
  overriding system value values (951, 'cccccccc-0000-0000-0000-000000006501'::uuid, 951, 1, 'PENDING_PAYMENT');

-- ------------------------------------------------- 1: signature surface
select has_function('public', 'record_webhook_payment',
  array['text', 'text', 'int', 'boolean', 'jsonb'],
  'record_webhook_payment RPC should exist');
select has_function('public', 'create_pending_payment',
  array['bigint', 'numeric', 'text'],
  'create_pending_payment stays intact');

-- ------------------------------------------------- 2..4: webhook upsert
-- existing row: unpaid outcome -> FAILED with raw payload kept
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select public.create_pending_payment(951, 200, null);
update public.payments set merchant_order_id = '651' where merchant_order_id = (
  select id::text from public.payments where booking_id = 951 order by id desc limit 1);

select set_eq(
  $$ select status::text from public.payments where merchant_order_id = '651' $$,
  array['CREATED'],
  'fixture payment CREATED before webhook'
);

select record_webhook_payment('651', 'txn65_hook', 200, false, '{"obj": {"success": false}}'::jsonb);

-- ------------------------------------------------- asserts as superuser
reset role;

select ok(
  (select count(*) from public.payments
    where merchant_order_id = '651' and status = 'FAILED'
      and raw_webhook->>'obj' is not null and gateway_ref = 'txn65_hook') = 1,
  'webhook outcome flips existing CREATED to FAILED keeping raw payload'
);

-- orphan insert for unknown order
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select record_webhook_payment('652', 'txn65_orphan', 300, false, '{}'::jsonb);
reset role;
select ok(
  (select count(*) from public.payments
    where merchant_order_id = '652' and booking_id is null and status = 'FAILED') = 1,
  'unknown order inserts orphan FAILED payment (booking_id NULL)'
);

-- PAID terminality: already_paid flag, row untouched
set local role postgres;
update public.payments set status = 'PAID' where merchant_order_id = '652';
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select ok(
  (record_webhook_payment('652', 'again', 300, true, '{}'::jsonb)->>'already_paid')::boolean,
  'PAID row acknowledged via already_paid flag'
);
reset role;
select ok(
  (select count(*) from public.payments where merchant_order_id = '652') = 1,
  'no duplicate rows after PAID webhook replay'
);

-- authenticated denied
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006501"}';
select throws_ok(
  $$ select public.record_webhook_payment('x', 'y', 1, false, '{}'::jsonb) $$,
  '42501', null,
  'authenticated caller denied record_webhook_payment'
);

-- ------------------------------------------------- 8: mark_payment_failed detail
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select throws_ok(
  $$ select public.mark_payment_failed(999999999::bigint, '{"r":"x"}'::jsonb) $$,
  'P0002', null,
  'mark_payment_failed raises PAYMENT_NOT_FOUND for unknown id'
);

select * from finish();
rollback;
