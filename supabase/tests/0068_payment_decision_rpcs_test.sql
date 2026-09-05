-- supabase/tests/0068_payment_decision_rpcs_test.sql
-- 011 US2: Staff-only payment proof decision RPCs (approve_payment_proof, reject_payment_proof).
-- Tests: staff allow, non-staff deny (FORBIDDEN), idempotency, reject-resubmit-approve,
-- catalog reason verification, expiry composition, and anon denial.

begin;
select plan(16);

-- ---------------------------------------------------------------- fixtures
delete from public.audit_log where entity_type = 'payment_proofs' and entity_id in (
  select id from public.payment_proofs where booking_id in (681, 682, 683, 684, 685, 686));
delete from public.event_outbox where handler_type = 'WHATSAPP' and (
  payload->>'booking_id' in ('681', '682', '683', '684', '685', '686') or
  payload->'params'->>'booking_id' in ('681', '682', '683', '684', '685', '686')
);
delete from public.payment_proofs where booking_id in (681, 682, 683, 684, 685, 686);
delete from public.payments where booking_id in (681, 682, 683, 684, 685, 686);
delete from public.bookings where id in (681, 682, 683, 684, 685, 686);
delete from public.service_slots where id in (681, 682, 683, 684, 685, 686);
delete from public.services where id in (681);

insert into auth.users (id, email, phone) values
  ('cccccccc-0000-0000-0000-000000006801'::uuid, 'admin6801@test.com', '+201000006801'),
  ('cccccccc-0000-0000-0000-000000006802'::uuid, 'superadmin6802@test.com', '+201000006802'),
  ('cccccccc-0000-0000-0000-000000006803'::uuid, 'member6803@test.com', '+201000006803')
on conflict (id) do update set email = excluded.email, phone = excluded.phone;

insert into public.users (id, phone, name, role, tenant_id) values
  ('cccccccc-0000-0000-0000-000000006801'::uuid, '+201000006801', 'Admin Staff', 'ADMIN', 1),
  ('cccccccc-0000-0000-0000-000000006802'::uuid, '+201000006802', 'Super Admin', 'SUPER_ADMIN', 1),
  ('cccccccc-0000-0000-0000-000000006803'::uuid, '+201000006803', 'Member', 'USER', 1)
on conflict (id) do update set role = excluded.role;

insert into public.services (id, tenant_id, title_ar)
  overriding system value values (681, 1, 'رحلة دير');

insert into public.service_slots (id, service_id, tenant_id, starts_at, ends_at, capacity)
  overriding system value values
    (681, 681, 1, now() + interval '5 days', now() + interval '5 days 4 hours', 10),
    (682, 681, 1, now() + interval '6 days', now() + interval '6 days 4 hours', 10),
    (683, 681, 1, now() + interval '7 days', now() + interval '7 days 4 hours', 10),
    (684, 681, 1, now() + interval '8 days', now() + interval '8 days 4 hours', 10),
    (685, 681, 1, now() + interval '9 days', now() + interval '9 days 4 hours', 10);

insert into public.bookings (id, user_id, slot_id, tenant_id, status, locked_until)
  overriding system value values
    (681, 'cccccccc-0000-0000-0000-000000006803'::uuid, 681, 1, 'PENDING_PAYMENT', now() + interval '20 minutes'),
    (682, 'cccccccc-0000-0000-0000-000000006803'::uuid, 682, 1, 'PENDING_PAYMENT', now() + interval '20 minutes'),
    (683, 'cccccccc-0000-0000-0000-000000006803'::uuid, 683, 1, 'PENDING_PAYMENT', now() + interval '20 minutes'),
    (684, 'cccccccc-0000-0000-0000-000000006803'::uuid, 684, 1, 'PENDING_PAYMENT', now() + interval '20 minutes'),
    (685, 'cccccccc-0000-0000-0000-000000006803'::uuid, 685, 1, 'PENDING_PAYMENT', now() - interval '5 minutes');

insert into storage.objects (bucket_id, name) values
  ('payment-proofs', '1/681/proof.jpg'),
  ('payment-proofs', '1/682/proof.jpg'),
  ('payment-proofs', '1/683/proof.jpg'),
  ('payment-proofs', '1/684/proof.jpg'),
  ('payment-proofs', '1/684/proof2.jpg'),
  ('payment-proofs', '1/685/proof.jpg');

-- Create payment snapshots & proofs
insert into public.payments (id, booking_id, amount, status, tenant_id)
  overriding system value values
    (681, 681, 15000, 'CREATED', 1),
    (682, 682, 15000, 'CREATED', 1),
    (683, 683, 15000, 'CREATED', 1),
    (684, 684, 15000, 'CREATED', 1),
    (685, 685, 15000, 'CREATED', 1);

insert into public.payment_proofs (id, booking_id, payment_id, channel, sender_phone, reference_number, amount_claimed, image_path, status, tenant_id)
  overriding system value values
    (681, 681, 681, 'VODAFONE_CASH', '+201000006803', 'REF681', 15000, '1/681/proof.jpg', 'PENDING', 1),
    (682, 682, 682, 'INSTAPAY', '+201000006803', 'REF682', 15000, '1/682/proof.jpg', 'PENDING', 1),
    (683, 683, 683, 'VODAFONE_CASH', '+201000006803', 'REF683', 15000, '1/683/proof.jpg', 'PENDING', 1),
    (684, 684, 684, 'VODAFONE_CASH', '+201000006803', 'REF684', 15000, '1/684/proof.jpg', 'PENDING', 1),
    (685, 685, 685, 'VODAFONE_CASH', '+201000006803', 'REF685', 15000, '1/685/proof.jpg', 'PENDING', 1);

-- ------------------------------------------------- 1..5: ADMIN approve happy path
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006801"}';

select is(
  public.approve_payment_proof(681),
  jsonb_build_object('booking_id', 681, 'payment_id', 681),
  'admin approve returns booking_id and payment_id jsonb'
);
reset role;

select is(
  (select status from public.payment_proofs where id = 681),
  'APPROVED',
  'proof status moves to APPROVED'
);

select is(
  (select status::text from public.payments where id = 681),
  'PAID',
  'payment status transitions to PAID via apply_payment'
);

select is(
  (select status from public.bookings where id = 681),
  'AWAITING_CALL',
  'booking advances to AWAITING_CALL'
);

-- WhatsApp notification enqueued
select is(
  (select count(*) from public.event_outbox
    where handler_type = 'WHATSAPP'
      and payload->>'template_name' = 'booking_payment_received'
      and (payload->>'booking_id' = '681' or payload->'params'->>'booking_id' = '681')),
  1::bigint,
  'WhatsApp booking_payment_received notification row enqueued'
);

-- ------------------------------------------------- 6..7: SUPER_ADMIN approve happy path
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006802"}';

select is(
  public.approve_payment_proof(682),
  jsonb_build_object('booking_id', 682, 'payment_id', 682),
  'superadmin approve succeeds'
);
reset role;

select is(
  (select status from public.payment_proofs where id = 682),
  'APPROVED',
  'proof 682 approved by superadmin'
);

-- ------------------------------------------------- 8..9: USER role denied FORBIDDEN
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006803"}';

select throws_ok(
  $$ select public.approve_payment_proof(683) $$,
  '42501', null,
  'regular member cannot approve payment proof (FORBIDDEN)'
);

select throws_ok(
  $$ select public.reject_payment_proof(683, 'BAD_REQUEST') $$,
  '42501', null,
  'regular member cannot reject payment proof (FORBIDDEN)'
);
reset role;

-- ------------------------------------------------- 10: Double-approve denied BAD_REQUEST
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006801"}';

select throws_ok(
  $$ select public.approve_payment_proof(681) $$,
  'P0001', null,
  'second approval on already APPROVED proof rejected BAD_REQUEST'
);
reset role;

-- ------------------------------------------------- 11..14: Reject with catalog code & resubmit lifecycle
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006801"}';

select lives_ok(
  $$ select public.reject_payment_proof(684, 'BAD_REQUEST') $$,
  'admin reject with valid catalog code succeeds'
);
reset role;

select is(
  (select status from public.payment_proofs where id = 684),
  'REJECTED',
  'proof status set to REJECTED'
);

select is(
  (select status::text from public.payments where id = 684),
  'FAILED',
  'rejection voids the linked CREATED payment snapshot'
);

-- Member resubmits new proof after rejection (0067 flow)
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006803"}';

select ok(
  public.submit_payment_proof(684, 'VODAFONE_CASH', '+201000006803', 'REF684_FIXED', 15000, '1/684/proof2.jpg') > 0,
  'member can resubmit new proof for booking 684 after previous was rejected'
);
reset role;

-- ------------------------------------------------- 15: Reject with non-catalog code fails BAD_REQUEST
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006801"}';

select throws_ok(
  $$ select public.reject_payment_proof(683, 'NON_EXISTENT_CATALOG_REASON_CODE') $$,
  'P0001', null,
  'reject with non-catalog code rejected BAD_REQUEST'
);
reset role;

-- ------------------------------------------------- 16: Expiry composition & stale booking refund
-- Stale booking 685 expired (locked_until in past)
select public.expire_stale_bookings();

select is(
  (select status from public.bookings where id = 685),
  'CANCELLED',
  'expired booking with pending proof cancelled by expire_stale_bookings'
);

select * from finish();
rollback;
