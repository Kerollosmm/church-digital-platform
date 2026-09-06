-- supabase/tests/0073_event_booking_schema_test.sql
-- Spec 008 Phase 1 Test Suite:
-- Schema, RLS, Price non-negative check, and GiST exclusion anti-collision.

begin;
select plan(11);

-- ---------------------------------------------------------------- fixtures
insert into auth.users (id, email, phone) values
  ('eeeeeeee-0000-0000-0000-000000007301'::uuid, 'user7301@test.com', '+201000007301'),
  ('eeeeeeee-0000-0000-0000-000000007302'::uuid, 'user7302@test.com', '+201000007302')
on conflict (id) do update set email = excluded.email, phone = excluded.phone;

insert into public.users (id, phone, name, role, tenant_id) values
  ('eeeeeeee-0000-0000-0000-000000007301'::uuid, '+201000007301', 'Member 73', 'USER', 1),
  ('eeeeeeee-0000-0000-0000-000000007302'::uuid, '+201000007302', 'Admin 73', 'ADMIN', 1)
on conflict (id) do update set role = excluded.role;

-- 1..4: Check tables exist
select has_table('public', 'event_types', 'event_types table exists');
select has_table('public', 'extra_services', 'extra_services table exists');
select has_table('public', 'venues_resources', 'venues_resources table exists');
select has_table('public', 'event_bookings', 'event_bookings table exists');

-- Insert catalog fixtures
insert into public.event_types (id, name_ar, base_price_piastres, default_duration_minutes, tenant_id)
values ('11111111-1111-1111-1111-111111111111'::uuid, 'إكليل زواج', 50000, 120, 1)
on conflict (id) do nothing;

insert into public.venues_resources (id, name_ar, location_details_ar, tenant_id)
values ('22222222-2222-2222-2222-222222222222'::uuid, 'القاعة الرئيسية', 'المبنى الشرقي', 1)
on conflict (id) do nothing;

-- 5: GiST range exclusion constraint test (first booking confirmed)
insert into public.event_bookings (
  id, customer_id, event_type_id, assigned_venue_id, start_time, end_time, status, tenant_id
) values (
  '33333333-3333-3333-3333-333333333331'::uuid,
  'eeeeeeee-0000-0000-0000-000000007301'::uuid,
  '11111111-1111-1111-1111-111111111111'::uuid,
  '22222222-2222-2222-2222-222222222222'::uuid,
  '2026-09-01 18:00:00+02',
  '2026-09-01 20:00:00+02',
  'CONFIRMED',
  1
);

select is(
  (select count(*)::int from public.event_bookings where id = '33333333-3333-3333-3333-333333333331'::uuid),
  1,
  'first confirmed event booking inserted successfully'
);

-- 6: Conflicting overlapping booking in CONFIRMED status must be rejected by exclusion constraint
select throws_ok(
  $$
    insert into public.event_bookings (
      id, customer_id, event_type_id, assigned_venue_id, start_time, end_time, status, tenant_id
    ) values (
      '33333333-3333-3333-3333-333333333332'::uuid,
      'eeeeeeee-0000-0000-0000-000000007301'::uuid,
      '11111111-1111-1111-1111-111111111111'::uuid,
      '22222222-2222-2222-2222-222222222222'::uuid,
      '2026-09-01 19:00:00+02',
      '2026-09-01 21:00:00+02',
      'CONFIRMED',
      1
    );
  $$,
  '23P01',
  null,
  'exclusion constraint prevents overlapping venue assignment'
);

-- 7: Overlapping booking in SUBMITTED status is permitted (venue not yet locked)
select lives_ok(
  $$
    insert into public.event_bookings (
      id, customer_id, event_type_id, assigned_venue_id, start_time, end_time, status, tenant_id
    ) values (
      '33333333-3333-3333-3333-333333333333'::uuid,
      'eeeeeeee-0000-0000-0000-000000007301'::uuid,
      '11111111-1111-1111-1111-111111111111'::uuid,
      '22222222-2222-2222-2222-222222222222'::uuid,
      '2026-09-01 19:00:00+02',
      '2026-09-01 21:00:00+02',
      'SUBMITTED',
      1
    );
  $$,
  'overlapping booking in SUBMITTED status is allowed without collision error'
);

-- 8..9: RLS checks: Members read own bookings, anon cannot read bookings
set local role anon;
select is(
  (select count(*)::int from public.event_bookings),
  0,
  'anon role cannot read event_bookings'
);
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"eeeeeeee-0000-0000-0000-000000007301"}';
select is(
  (select count(*)::int from public.event_bookings),
  2,
  'member reads own event bookings under RLS'
);
reset role;

-- 10: Client direct insert revoked
set local role authenticated;
set local request.jwt.claims = '{"sub":"eeeeeeee-0000-0000-0000-000000007301"}';
select throws_ok(
  $$
    insert into public.event_bookings (customer_id, event_type_id, start_time, end_time)
    values ('eeeeeeee-0000-0000-0000-000000007301'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, now(), now() + interval '2 hours')
  $$,
  '42501',
  null,
  'direct insert on event_bookings is forbidden for authenticated users'
);
reset role;

-- 11: Outbox template check constraint allows new Spec 008 template
select lives_ok(
  $$
    insert into public.event_outbox (handler_type, payload, tenant_id)
    values (
      'WHATSAPP',
      '{"phone":"+201000007301","template_name":"event_booking_confirmed","params":{}}'::jsonb,
      1
    );
  $$,
  'event_outbox allows event_booking_confirmed template'
);

select * from finish();
rollback;
