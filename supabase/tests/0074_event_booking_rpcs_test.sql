-- supabase/tests/0074_event_booking_rpcs_test.sql
-- Spec 008 Phase 2 Test Suite:
-- Stored Procedures (submit_event_booking, admin_confirm_booking, admin_reject_booking, admin_record_cash_payment)

begin;
select plan(12);

-- ---------------------------------------------------------------- fixtures
insert into auth.users (id, email, phone) values
  ('ffffffff-0000-0000-0000-000000007401'::uuid, 'user7401@test.com', '+201000007401'),
  ('ffffffff-0000-0000-0000-000000007402'::uuid, 'user7402@test.com', '+201000007402')
on conflict (id) do update set email = excluded.email, phone = excluded.phone;

insert into public.users (id, phone, name, role, tenant_id) values
  ('ffffffff-0000-0000-0000-000000007401'::uuid, '+201000007401', 'Member 74', 'USER', 1),
  ('ffffffff-0000-0000-0000-000000007402'::uuid, '+201000007402', 'Admin 74', 'ADMIN', 1)
on conflict (id) do update set role = excluded.role;

insert into public.event_types (id, name_ar, base_price_piastres, default_duration_minutes, tenant_id)
values ('aaaaaaaa-1111-1111-1111-111111111111'::uuid, 'معمودية', 25000, 60, 1)
on conflict (id) do nothing;

insert into public.extra_services (id, name_ar, price_piastres, is_quantity_based, max_quantity, tenant_id)
values
  ('bbbbbbbb-1111-1111-1111-111111111111'::uuid, 'تصوير فوتوغرافي', 15000, false, 1, 1),
  ('bbbbbbbb-2222-2222-2222-222222222222'::uuid, 'كراسي إضافية', 1000, true, 50, 1)
on conflict (id) do nothing;

insert into public.event_type_extra_services (event_type_id, extra_service_id, tenant_id)
values
  ('aaaaaaaa-1111-1111-1111-111111111111'::uuid, 'bbbbbbbb-1111-1111-1111-111111111111'::uuid, 1),
  ('aaaaaaaa-1111-1111-1111-111111111111'::uuid, 'bbbbbbbb-2222-2222-2222-222222222222'::uuid, 1)
on conflict do nothing;

insert into public.venues_resources (id, name_ar, location_details_ar, tenant_id)
values
  ('cccccccc-1111-1111-1111-111111111111'::uuid, 'معمودية الكنيسة الكبرى', 'الدور الأرضي', 1),
  ('cccccccc-2222-2222-2222-222222222222'::uuid, 'قاعة المناسبات', 'المبنى الخدمي', 1)
on conflict (id) do nothing;

-- ------------------------------------------------- 1..4: submit_event_booking
set local role authenticated;
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007401"}';

select throws_ok(
  $$
    select public.submit_event_booking(
      'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
      now() - interval '1 hour',
      '[]'::jsonb
    )
  $$,
  'P0001',
  null,
  'booking submission in the past fails with BAD_REQUEST'
);

select lives_ok(
  $$
    select public.submit_event_booking(
      'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
      now() + interval '5 days',
      '[
        {"extra_service_id":"bbbbbbbb-1111-1111-1111-111111111111", "quantity":1},
        {"extra_service_id":"bbbbbbbb-2222-2222-2222-222222222222", "quantity":10}
      ]'::jsonb,
      'ملاحظات خاصة بالمناسبة'
    )
  $$,
  'valid event booking submission succeeds'
);
reset role;

select is(
  (select count(*)::int from public.event_bookings where customer_id = 'ffffffff-0000-0000-0000-000000007401'::uuid and status = 'SUBMITTED'),
  1,
  'event booking inserted with SUBMITTED status'
);

-- Total calculation: 25000 base + 15000 photo + (1000 * 10 chairs) = 50000 piastres
select is(
  (select total_price_piastres from public.event_bookings where customer_id = 'ffffffff-0000-0000-0000-000000007401'::uuid limit 1),
  50000::bigint,
  'total price snapshot correctly computed in piastres'
);

-- ------------------------------------------------- 5..7: admin_confirm_booking
set local role authenticated;
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007401"}';

-- Non-admin cannot confirm booking
select throws_ok(
  $$
    select public.admin_confirm_booking(
      (select id from public.event_bookings where customer_id = 'ffffffff-0000-0000-0000-000000007401'::uuid limit 1),
      'cccccccc-1111-1111-1111-111111111111'::uuid
    )
  $$,
  '42501',
  null,
  'regular user cannot confirm booking (FORBIDDEN)'
);
reset role;

-- Admin confirms booking
set local role authenticated;
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007402"}';

select lives_ok(
  $$
    select public.admin_confirm_booking(
      (select id from public.event_bookings where customer_id = 'ffffffff-0000-0000-0000-000000007401'::uuid limit 1),
      'cccccccc-1111-1111-1111-111111111111'::uuid,
      null,
      null,
      'تم التأكيد هاتفياً'
    )
  $$,
  'admin confirms booking and assigns venue'
);
reset role;

select is(
  (select status::text from public.event_bookings where customer_id = 'ffffffff-0000-0000-0000-000000007401'::uuid limit 1),
  'CONFIRMED',
  'booking status updated to CONFIRMED'
);

-- ------------------------------------------------- 8..9: admin_record_cash_payment
set local role authenticated;
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007402"}';

-- Partial cash payment (20000 out of 50000)
select lives_ok(
  $$
    select public.admin_record_cash_payment(
      (select id from public.event_bookings where customer_id = 'ffffffff-0000-0000-0000-000000007401'::uuid limit 1),
      20000,
      'عربون نقدي بالخزينة'
    )
  $$,
  'admin records partial cash payment'
);

-- Settle remaining balance (30000) -> Status transitions to PAID
select lives_ok(
  $$
    select public.admin_record_cash_payment(
      (select id from public.event_bookings where customer_id = 'ffffffff-0000-0000-0000-000000007401'::uuid limit 1),
      30000,
      'استكمال المبلغ بالكامل'
    )
  $$,
  'admin settles full balance'
);
reset role;

select is(
  (select status::text from public.event_bookings where customer_id = 'ffffffff-0000-0000-0000-000000007401'::uuid limit 1),
  'PAID',
  'booking transitions to PAID when fully settled'
);

select is(
  (select count(*)::int from public.payment_audit_logs where booking_id = (select id from public.event_bookings where customer_id = 'ffffffff-0000-0000-0000-000000007401'::uuid limit 1)),
  2,
  'immutable payment audit log recorded 2 cash entries'
);

-- ------------------------------------------------- 10: admin_reject_booking
-- Create a new booking to test rejection
insert into public.event_bookings (
  id, customer_id, event_type_id, start_time, end_time, status, tenant_id
) values (
  'dddddddd-1111-1111-1111-111111111111'::uuid,
  'ffffffff-0000-0000-0000-000000007401'::uuid,
  'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
  now() + interval '10 days',
  now() + interval '10 days 1 hour',
  'SUBMITTED',
  1
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007402"}';
select lives_ok(
  $$
    select public.admin_reject_booking(
      'dddddddd-1111-1111-1111-111111111111'::uuid,
      'الموعد غير متاح لأسباب رعوية'
    )
  $$,
  'admin rejects booking with reason'
);
reset role;

select * from finish();
rollback;
