-- supabase/tests/0064_transition_owner_guard_test.sql
-- 010-fix-review-findings US1: ownership guard on transition_booking_status
-- + additive payment lifecycle RPCs create_pending_payment / mark_payment_failed
-- Role hygiene: state assertions run as postgres superuser; privileged calls
-- switch to service_role/authenticated explicitly.

begin;
select plan(9);

-- ---------------------------------------------------------------- fixtures
delete from public.payments where id in (99981, 99982, 99983);
delete from public.bookings where id in (901, 902);
delete from public.service_slots where id in (901, 902);
delete from public.services where id in (901, 902);

insert into auth.users (id, email, phone) values
  ('cccccccc-0000-0000-0000-000000006401'::uuid, 'user6401@test.com', '+201000006401'),
  ('cccccccc-0000-0000-0000-000000006402'::uuid, 'user6402@test.com', '+201000006402')
on conflict (id) do update set email = excluded.email, phone = excluded.phone;

insert into public.users (id, phone, name, role, tenant_id) values
  ('cccccccc-0000-0000-0000-000000006401'::uuid, '+201000006401', 'Owner A', 'USER', 1),
  ('cccccccc-0000-0000-0000-000000006402'::uuid, '+201000006402', 'Outsider B', 'USER', 1)
on conflict (id) do update set role = 'USER', phone = excluded.phone;

insert into public.services (id, tenant_id, title_ar)
  overriding system value values (901, 1, 'قداس'), (902, 1, 'اعتراف');

insert into public.service_slots (id, service_id, tenant_id, starts_at, ends_at, capacity)
  overriding system value values
  (901, 901, 1, now() + interval '1 day', now() + interval '1 day 2 hours', 10),
  (902, 902, 1, now() + interval '2 days', now() + interval '2 days 3 hours', 10);

insert into public.bookings (id, user_id, slot_id, tenant_id, status)
  overriding system value values
  (901, 'cccccccc-0000-0000-0000-000000006401'::uuid, 901, 1, 'PENDING_PAYMENT'),
  (902, 'cccccccc-0000-0000-0000-000000006401'::uuid, 902, 1, 'PENDING_PAYMENT');

insert into public.payments (id, booking_id, amount, status, gateway_ref, tenant_id)
  overriding system value values
  (99981, 901, 100, 'CREATED', 'txn64_created', 1),
  (99983, 902, 100, 'PAID',   'txn64_paid',   1);

-- ------------------------------------------------- 1..4: ownership guard
-- 1. Non-owner CANNOT advance someone else's booking via apply_payment escape hatch
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006402"}';
select throws_ok(
  $$ select public.transition_booking_status(901, 'AWAITING_CALL', 'apply_payment') $$,
  '42501', null,
  'non-owner must be denied even with p_action=apply_payment'
);

-- 2. Owner CAN record own payment transition
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006401"}';
select ok(
  (public.transition_booking_status(901, 'AWAITING_CALL', 'apply_payment')).status = 'AWAITING_CALL',
  'owner apply_payment advances own booking to AWAITING_CALL'
);
reset role;

-- 3. audit row written for the owner transition (read as superuser: audit_log RLS)
select ok(
  exists (select 1 from public.audit_log
          where entity_type = 'bookings' and entity_id = 901 and action = 'apply_payment'
            and meta->>'new_status' = 'AWAITING_CALL'),
  'audit row written for owner apply_payment transition'
);

-- 4. service_role CAN transition (admin-tier operations, e.g. confirmation)
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select public.transition_booking_status(901, 'CONFIRMED', 'confirm_booking');
reset role;
select ok(
  (select status::text from public.bookings where id = 901) = 'CONFIRMED',
  'service_role can advance booking to CONFIRMED'
);

-- ------------------------------------------------- 5..6: lifecycle RPC surface
select has_function('public', 'create_pending_payment', array['bigint', 'numeric', 'text'],
  'create_pending_payment RPC should exist');
select has_function('public', 'mark_payment_refunded', array['bigint'],
  'mark_payment_refunded stays intact');

-- ------------------------------------------------- 7..9: create_pending_payment
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select public.create_pending_payment(902, 150, 'txn64_new');
reset role;
select ok(
  (select status::text from public.payments where gateway_ref = 'txn64_new') = 'CREATED',
  'create_pending_payment inserts CREATED payment without advancing booking'
);
select ok(
  (select status::text from public.bookings where id = 902) = 'PENDING_PAYMENT',
  'booking stays PENDING_PAYMENT after create_pending_payment'
);

-- owner can create a pending payment for own booking
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006401"}';
select public.create_pending_payment(902, 120, 'txn64_owner');
reset role;
select ok(
  (select status::text from public.payments where gateway_ref = 'txn64_owner') = 'CREATED',
  'owner can create pending payment on own booking'
);

-- non-owner denied
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006402"}';
select throws_ok(
  $$ select public.create_pending_payment(902, 100, 'txn64_bad') $$,
  '42501', null,
  'non-owner denied create_pending_payment on someone else''s booking'
);

select * from finish();
rollback;
