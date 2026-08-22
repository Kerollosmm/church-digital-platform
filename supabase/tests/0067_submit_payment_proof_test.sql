-- supabase/tests/0067_submit_payment_proof_test.sql
-- 011 US1: owner-only payment proof submission via submit_payment_proof.
-- Owner allow + snapshot semantics; ownership/status/channel/image guards;
-- anon denial; audit trail.

begin;
select plan(12);

-- ---------------------------------------------------------------- fixtures
delete from public.audit_log where entity_type = 'payment_proofs' and entity_id in (
  select id from public.payment_proofs where booking_id in (661, 662));
delete from public.payment_proofs where booking_id in (661, 662);
delete from public.payments where booking_id in (661, 662);
delete from public.bookings where id in (661, 662);
delete from public.service_slots where id in (661, 662);
delete from public.services where id in (661);

insert into auth.users (id, email, phone) values
  ('cccccccc-0000-0000-0000-000000006701'::uuid, 'user6701@test.com', '+201000006701'),
  ('cccccccc-0000-0000-0000-000000006702'::uuid, 'user6702@test.com', '+201000006702')
on conflict (id) do update set email = excluded.email, phone = excluded.phone;

insert into public.users (id, phone, name, role, tenant_id) values
  ('cccccccc-0000-0000-0000-000000006701'::uuid, '+201000006701', 'Owner', 'USER', 1),
  ('cccccccc-0000-0000-0000-000000006702'::uuid, '+201000006702', 'Other', 'USER', 1)
on conflict (id) do update set role = excluded.role;

insert into public.services (id, tenant_id, title_ar)
  overriding system value values (661, 1, 'قداس');
insert into public.service_slots (id, service_id, tenant_id, starts_at, ends_at, capacity)
  overriding system value values (661, 661, 1, now() + interval '4 days', now() + interval '4 days 2 hours', 5),
                                 (662, 661, 1, now() + interval '5 days', now() + interval '5 days 2 hours', 5);
insert into public.bookings (id, user_id, slot_id, tenant_id, status)
  overriding system value values (661, 'cccccccc-0000-0000-0000-000000006701'::uuid, 661, 1, 'PENDING_PAYMENT'),
                                 (662, 'cccccccc-0000-0000-0000-000000006701'::uuid, 662, 1, 'AWAITING_CALL');

-- uploaded screenshot object under the caller prefix (success-case guard)
insert into storage.objects (bucket_id, name) values ('payment-proofs', '1/661/proof.jpg');

-- ------------------------------------------------- 1..4: owner happy path
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006701"}';
select ok(
  public.submit_payment_proof(661, 'VODAFONE_CASH', '+201000006701', 'ref67001', 200, '1/661/proof.jpg') > 0,
  'owner submit returns a proof id'
);
reset role;

select is(
  (select count(*) from public.payment_proofs
    where booking_id = 661 and channel = 'VODAFONE_CASH' and status = 'PENDING'
      and reference_number = 'ref67001' and amount_claimed = 200
      and image_path = '1/661/proof.jpg'
      and payment_id is not null),
  1::bigint,
  'PENDING proof recorded with wallet details and payment snapshot link'
);

select set_eq(
  $$ select status::text from public.payments where booking_id = 661 $$,
  array['CREATED'],
  'submission snapshots a CREATED payment only — nothing financial moves'
);

select is(
  (select count(*) from public.bookings where id = 661 and status = 'PENDING_PAYMENT'), 1::bigint,
  'booking stays PENDING_PAYMENT after submission'
);

-- ------------------------------------------------- 5: audit trail
select is(
  (select count(*) from public.audit_log
    where action = 'submit_payment_proof' and entity_type = 'payment_proofs'),
  1::bigint,
  'audit row written on successful submission'
);

-- ------------------------------------------------- 6: non-owner denied
delete from public.payments where booking_id = 662;

set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006702"}';
select throws_ok(
  $$ select public.submit_payment_proof(661, 'INSTAPAY', '+201000006702', 'refX', 200, null) $$,
  '42501', null,
  'non-owner submission raises FORBIDDEN'
);
reset role;

select is(
  (select count(*) from public.payment_proofs where reference_number = 'refX'), 0::bigint,
  'non-owner denial writes zero proof rows'
);

-- ------------------------------------------------- 8: wallet without image
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006701"}';
select throws_ok(
  $$ select public.submit_payment_proof(661, 'VODAFONE_CASH', '+201000006701', 'refNoImg', 200, null) $$,
  'P0001', null,
  'wallet channel without image rejected BAD_REQUEST'
);

-- ------------------------------------------------- 9: CASH with image
select throws_ok(
  $$ select public.submit_payment_proof(661, 'CASH', '+201000006701', 'refCashImg', 100, '1/661/cash.jpg') $$,
  'P0001', null,
  'CASH channel carrying an image rejected BAD_REQUEST'
);

-- ------------------------------------------------- 10: duplicate PENDING
select throws_ok(
  $$ select public.submit_payment_proof(661, 'CASH', '+201000006701', 'refDup', 200, null) $$,
  'P0001', null,
  'second PENDING proof for same booking rejected BAD_REQUEST'
);

-- ------------------------------------------------- 11: booking not awaiting payment
select throws_ok(
  $$ select public.submit_payment_proof(662, 'CASH', '+201000006701', 'refLate', 100, null) $$,
  'P0001', null,
  'submission against non-PENDING_PAYMENT booking rejected BAD_REQUEST'
);

-- ------------------------------------------------- anon denied
set local role anon;
select throws_ok(
  $$ select public.submit_payment_proof(661, 'CASH', 'x', 'y', 1, null) $$,
  '42501', null,
  'anon execution denied (no EXECUTE grant)'
);

select * from finish();
rollback;
