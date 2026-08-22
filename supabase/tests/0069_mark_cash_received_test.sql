-- supabase/tests/0069_mark_cash_received_test.sql
-- 011 US3: Staff-only mark_cash_received RPC
-- Tests: staff allow, non-staff deny (FORBIDDEN), booking status guard,
-- conflict with existing pending proof, positive amount validation, and WhatsApp outbox.

begin;
select plan(12);

-- ---------------------------------------------------------------- fixtures
delete from public.audit_log where entity_type in ('payment_proofs', 'payments', 'bookings') and entity_id in (691, 692, 693, 694, 695);
delete from public.event_outbox where handler_type = 'WHATSAPP' and (
  payload->>'booking_id' in ('691', '692', '693', '694', '695') or
  payload->'params'->>'booking_id' in ('691', '692', '693', '694', '695')
);
delete from public.payment_proofs where booking_id in (691, 692, 693, 694, 695);
delete from public.payments where booking_id in (691, 692, 693, 694, 695);
delete from public.bookings where id in (691, 692, 693, 694, 695);
delete from public.service_slots where id in (691, 692, 693, 694, 695);
delete from public.services where id in (691);

insert into auth.users (id, email, phone) values
  ('dddddddd-0000-0000-0000-000000006901'::uuid, 'admin6901@test.com', '+201000006901'),
  ('dddddddd-0000-0000-0000-000000006902'::uuid, 'superadmin6902@test.com', '+201000006902'),
  ('dddddddd-0000-0000-0000-000000006903'::uuid, 'member6903@test.com', '+201000006903')
on conflict (id) do update set email = excluded.email, phone = excluded.phone;

insert into public.users (id, phone, name, role, tenant_id) values
  ('dddddddd-0000-0000-0000-000000006901'::uuid, '+201000006901', 'Admin Staff', 'ADMIN', 1),
  ('dddddddd-0000-0000-0000-000000006902'::uuid, '+201000006902', 'Super Admin', 'SUPER_ADMIN', 1),
  ('dddddddd-0000-0000-0000-000000006903'::uuid, '+201000006903', 'Member', 'USER', 1)
on conflict (id) do update set role = excluded.role;

insert into public.services (id, tenant_id, title_ar)
  overriding system value values (691, 1, 'حجز قاعة مناسبات');

insert into public.service_slots (id, service_id, tenant_id, starts_at, ends_at, capacity)
  overriding system value values
    (691, 691, 1, now() + interval '5 days', now() + interval '5 days 4 hours', 10),
    (692, 691, 1, now() + interval '6 days', now() + interval '6 days 4 hours', 10),
    (693, 691, 1, now() + interval '7 days', now() + interval '7 days 4 hours', 10),
    (694, 691, 1, now() + interval '8 days', now() + interval '8 days 4 hours', 10),
    (695, 691, 1, now() + interval '9 days', now() + interval '9 days 4 hours', 10);

insert into public.bookings (id, user_id, slot_id, tenant_id, status, locked_until)
  overriding system value values
    (691, 'dddddddd-0000-0000-0000-000000006903'::uuid, 691, 1, 'PENDING_PAYMENT', now() + interval '20 minutes'),
    (692, 'dddddddd-0000-0000-0000-000000006903'::uuid, 692, 1, 'PENDING_PAYMENT', now() + interval '20 minutes'),
    (693, 'dddddddd-0000-0000-0000-000000006903'::uuid, 693, 1, 'CONFIRMED', null),
    (694, 'dddddddd-0000-0000-0000-000000006903'::uuid, 694, 1, 'PENDING_PAYMENT', now() + interval '20 minutes');

insert into storage.objects (bucket_id, name) values
  ('payment-proofs', '1/694/proof.jpg');

-- Booking 694 already has a PENDING proof
insert into public.payments (id, booking_id, amount, status, tenant_id)
  overriding system value values (694, 694, 200, 'CREATED', 1);

insert into public.payment_proofs (id, booking_id, payment_id, channel, sender_phone, reference_number, amount_claimed, image_path, status, tenant_id)
  overriding system value values
    (694, 694, 694, 'VODAFONE_CASH', '+201000006903', 'REF694', 200, '1/694/proof.jpg', 'PENDING', 1);

-- ------------------------------------------------- 1..5: ADMIN mark_cash_received happy path
set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-0000-0000-0000-000000006901"}';

select is(
  (public.mark_cash_received(691, 250, 'استلم بالخزينة دياكون يوسف')->>'booking_id')::bigint,
  691::bigint,
  'admin mark_cash_received returns jsonb with booking_id'
);
reset role;

select is(
  (select status from public.payment_proofs where booking_id = 691),
  'APPROVED',
  'cash payment proof is inserted with APPROVED status'
);

select is(
  (select collector_note from public.payment_proofs where booking_id = 691),
  'استلم بالخزينة دياكون يوسف',
  'cash proof records collector note'
);

select is(
  (select status from public.bookings where id = 691),
  'AWAITING_CALL',
  'booking advances to AWAITING_CALL'
);

select is(
  (select count(*) from public.event_outbox
    where handler_type = 'WHATSAPP'
      and payload->>'template_name' = 'booking_payment_received'
      and (payload->>'booking_id' = '691' or payload->'params'->>'booking_id' = '691')),
  1::bigint,
  'WhatsApp booking_payment_received notification row enqueued'
);

-- ------------------------------------------------- 6..7: SUPER_ADMIN mark_cash_received happy path
set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-0000-0000-0000-000000006902"}';

select is(
  (public.mark_cash_received(692, 300)->>'booking_id')::bigint,
  692::bigint,
  'superadmin mark_cash_received succeeds'
);
reset role;

select is(
  (select status from public.bookings where id = 692),
  'AWAITING_CALL',
  'booking 692 advances to AWAITING_CALL'
);

-- ------------------------------------------------- 8: USER role denied FORBIDDEN
set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-0000-0000-0000-000000006903"}';

select throws_ok(
  $$ select public.mark_cash_received(691, 100) $$,
  '42501', null,
  'regular member cannot call mark_cash_received (FORBIDDEN)'
);
reset role;

-- ------------------------------------------------- 9: Non-PENDING_PAYMENT booking denied BAD_REQUEST
set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-0000-0000-0000-000000006901"}';

select throws_ok(
  $$ select public.mark_cash_received(693, 100) $$,
  'P0001', null,
  'booking not in PENDING_PAYMENT status rejected BAD_REQUEST'
);

-- ------------------------------------------------- 10: Existing PENDING proof conflict denied BAD_REQUEST
select throws_ok(
  $$ select public.mark_cash_received(694, 200) $$,
  'P0001', null,
  'booking with existing PENDING proof rejected BAD_REQUEST (decide proof first)'
);

-- ------------------------------------------------- 11: Non-positive amount denied BAD_REQUEST
select throws_ok(
  $$ select public.mark_cash_received(691, 0) $$,
  'P0001', null,
  'amount <= 0 rejected BAD_REQUEST'
);

-- ------------------------------------------------- 12: Non-existent booking denied BAD_REQUEST
select throws_ok(
  $$ select public.mark_cash_received(999999, 100) $$,
  'P0001', null,
  'non-existent booking rejected BAD_REQUEST'
);
reset role;

select * from finish();
rollback;
