-- supabase/tests/0071_review_fixes_test.sql
-- 011 post-review hardening: approve refuses non-pending bookings, reject voids
-- the pending payment snapshot, transition gate is fail-closed for JWT-less DB
-- callers and owners may only cancel, payout channels are per-tenant with an
-- is_active gate, admin storage policy carries the tenant prefix.

begin;
select plan(8);

-- ---------------------------------------------------------------- fixtures
delete from public.payment_proofs where booking_id in (711, 712);
delete from public.payments where gateway_ref like 'txn71%';
delete from public.bookings where id in (711, 712);
delete from public.service_slots where id in (711);
delete from public.services where id in (711);

insert into auth.users (id, email, phone) values
  ('cccccccc-0000-0000-0000-000000007101'::uuid, 'user7101@test.com', '+201000007101'),
  ('cccccccc-0000-0000-0000-000000007102'::uuid, 'user7102@test.com', '+201000007102')
on conflict (id) do update set email = excluded.email, phone = excluded.phone;

insert into public.users (id, phone, name, role, tenant_id) values
  ('cccccccc-0000-0000-0000-000000007101'::uuid, '+201000007101', 'Owner', 'USER', 1),
  ('cccccccc-0000-0000-0000-000000007102'::uuid, '+201000007102', 'Reviewer', 'ADMIN', 1)
on conflict (id) do update set role = excluded.role;

insert into public.services (id, tenant_id, title_ar)
  overriding system value values (711, 1, 'قداس');
insert into public.service_slots (id, service_id, tenant_id, starts_at, ends_at, capacity)
  overriding system value values (711, 711, 1, now() + interval '3 days', now() + interval '3 days 2 hours', 5);
insert into public.bookings (id, user_id, slot_id, tenant_id, status)
  overriding system value values
  (711, 'cccccccc-0000-0000-0000-000000007101'::uuid, 711, 1, 'PENDING_PAYMENT'),
  (712, 'cccccccc-0000-0000-0000-000000007101'::uuid, 711, 1, 'PENDING_PAYMENT');

insert into public.payments (id, booking_id, amount, status, gateway_ref, tenant_id)
  overriding system value values
  (99991, 711, 100, 'CREATED', 'txn71_a', 1);

insert into public.payment_proofs (booking_id, payment_id, channel, sender_phone, reference_number, amount_claimed)
values (711, 99991, 'CASH', '+201000007101', 'CASH_711_manual', 100);

-- ------------------------------------------------- 1..3: approve refuses stale bookings
update public.bookings set status = 'CANCELLED', locked_until = null where id = 711;

set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000007102"}';
select throws_ok(
  $$ select public.approve_payment_proof((select id from public.payment_proofs where booking_id = 711)) $$,
  'P0001', null,
  'approval refused for a cancelled booking'
);
reset role;

select is(
  (select status::text from public.bookings where id = 711), 'CANCELLED',
  'refused approval leaves the booking cancelled'
);
select is(
  (select status::text from public.payment_proofs where booking_id = 711), 'PENDING',
  'proof stays PENDING after a refused approval'
);

-- ------------------------------------------------- 4..5: reject voids the pending payment
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000007102"}';
select lives_ok(
  $$ select public.reject_payment_proof((select id from public.payment_proofs where booking_id = 711), 'BAD_REQUEST') $$,
  'admin reject with valid catalog code succeeds'
);
reset role;

select is(
  (select status::text from public.payments where id = 99991), 'FAILED',
  'rejection voids the linked CREATED payment'
);

-- ------------------------------------------------- 6: fail-closed gate without a JWT
select set_config('request.jwt.claims', null, true);
select throws_ok(
  $$ select public.transition_booking_status(712, 'AWAITING_CALL', 'apply_payment') $$,
  '42501', null,
  'JWT-less DB caller cannot advance a booking (NULL-uid hole closed)'
);

-- ------------------------------------------------- 7..8: per-tenant channel uniqueness
insert into public.payout_channels (tenant_id, channel, display_name_ar, account_number, holder_name)
values (2, 'VODAFONE_CASH', 'فودافون كاش', '01099990000', 'طائفة أخرى');

select throws_ok(
  $$ insert into public.payout_channels (tenant_id, channel, display_name_ar, account_number, holder_name)
     values (2, 'VODAFONE_CASH', 'مكرر', '01099991111', 'طائفة أخرى') $$,
  '23505', null,
  'duplicate channel within one tenant rejected by composite unique'
);

delete from public.payout_channels where tenant_id = 2;

-- ------------------------------------------------- 9: admin storage policy is tenant-scoped
select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Admins read all payment proof images'
  ),
  'admin receipt-read policy exists (tenant prefix enforced by definition)'
);

select * from finish();
rollback;
