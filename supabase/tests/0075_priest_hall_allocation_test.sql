-- supabase/tests/0075_priest_hall_allocation_test.sql
-- Spec 009: Smart Priest & Hall Allocation Matrix Test Suite

begin;
select plan(19);

-- ---------------------------------------------------------------- Fixtures
insert into auth.users (id, email, phone) values
  ('ffffffff-0000-0000-0000-000000007501'::uuid, 'user7501@test.com', '+201000007501'),
  ('ffffffff-0000-0000-0000-000000007502'::uuid, 'admin7502@test.com', '+201000007502')
on conflict (id) do update set email = excluded.email, phone = excluded.phone;

insert into public.users (id, phone, name, role, tenant_id) values
  ('ffffffff-0000-0000-0000-000000007501'::uuid, '+201000007501', 'Member 75', 'USER', 1),
  ('ffffffff-0000-0000-0000-000000007502'::uuid, '+201000007502', 'Admin 75', 'ADMIN', 1)
on conflict (id) do update set role = excluded.role;

insert into public.priests (id, name, phone, rank, tenant_id)
overriding system value
values
  (7501, 'أبونا أنطونيوس', '+201011117501', 'HEGUMEN', 1),
  (7502, 'أبونا ميخائيل', '+201022227502', 'PRIEST', 1)
on conflict (id) do update set name = excluded.name, phone = excluded.phone, rank = excluded.rank;

insert into public.event_types (id, name_ar, base_price_piastres, default_duration_minutes, tenant_id)
values ('aaaaaaaa-7501-0000-0000-000000000001'::uuid, 'إكليل مقدس', 50000, 120, 1)
on conflict (id) do nothing;

insert into public.venues_resources (id, name_ar, location_details_ar, tenant_id)
values
  ('cccccccc-7501-0000-0000-000000000001'::uuid, 'الكنيسة الكبرى', 'الدور الأرضي', 1),
  ('cccccccc-7502-0000-0000-000000000002'::uuid, 'كنيسة العذراء', 'الدور الأول', 1)
on conflict (id) do nothing;

insert into public.event_bookings (
  id, customer_id, event_type_id, assigned_venue_id, assigned_priest_id,
  start_time, end_time, status, base_price_piastres, total_price_piastres, tenant_id
) values (
  'bbbbbbbb-7501-0000-0000-000000000001'::uuid,
  'ffffffff-0000-0000-0000-000000007501'::uuid,
  'aaaaaaaa-7501-0000-0000-000000000001'::uuid,
  null,
  null,
  '2026-09-10 18:00:00+02'::timestamptz,
  '2026-09-10 20:00:00+02'::timestamptz,
  'SUBMITTED',
  50000,
  50000,
  1
), (
  'bbbbbbbb-7502-0000-0000-000000000002'::uuid,
  'ffffffff-0000-0000-0000-000000007501'::uuid,
  'aaaaaaaa-7501-0000-0000-000000000001'::uuid,
  null,
  null,
  '2026-09-10 18:30:00+02'::timestamptz,
  '2026-09-10 20:30:00+02'::timestamptz,
  'SUBMITTED',
  50000,
  50000,
  1
) on conflict (id) do nothing;

-- ------------------------------------------------- 1..3: Schema & Constraints Checks
select has_table('public', 'priest_schedules', 'priest_schedules table exists');
select has_column('public', 'event_bookings', 'assigned_priest_id', 'event_bookings has assigned_priest_id column');
select is(
  (select relrowsecurity from pg_class where relname = 'priest_schedules'),
  true,
  'priest_schedules has RLS enabled'
);

-- ------------------------------------------------- 4..6: Direct DML & GiST on priest_schedules
set local role authenticated;
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007501"}';

select throws_ok(
  $$
    insert into public.priest_schedules (priest_id, schedule_range, schedule_type, tenant_id)
    values (7501, tstzrange('2026-09-10 10:00:00+02', '2026-09-10 12:00:00+02'), 'LITURGY', 1);
  $$,
  '42501',
  null,
  'direct insert into priest_schedules is revoked for non-admin'
);
reset role;

select lives_ok(
  $$
    insert into public.priest_schedules (priest_id, schedule_range, schedule_type, tenant_id)
    values (7501, tstzrange('2026-09-10 10:00:00+02'::timestamptz, '2026-09-10 12:00:00+02'::timestamptz), 'LITURGY', 1);
  $$,
  'valid priest schedule insert succeeds'
);

-- Overlapping schedule for same priest throws exclusion_violation (23P01)
select throws_ok(
  $$
    insert into public.priest_schedules (priest_id, schedule_range, schedule_type, tenant_id)
    values (7501, tstzrange('2026-09-10 11:00:00+02'::timestamptz, '2026-09-10 13:00:00+02'::timestamptz), 'CONFESSION', 1);
  $$,
  '23P01',
  null,
  'overlapping priest schedule throws exclusion_violation 23P01'
);

-- ------------------------------------------------- 7..9: get_available_priests
-- Invalid time range check
select throws_ok(
  $$
    select * from public.get_available_priests(
      '2026-09-10 12:00:00+02'::timestamptz,
      '2026-09-10 10:00:00+02'::timestamptz
    );
  $$,
  'P0001',
  null,
  'get_available_priests with inverted range throws BAD_REQUEST'
);

-- Priest 7501 is busy 10:00-12:00, Priest 7502 is available
select is(
  (select count(*)::int from public.get_available_priests(
    '2026-09-10 10:30:00+02'::timestamptz,
    '2026-09-10 11:30:00+02'::timestamptz
  ) where id = 7501),
  0,
  'busy priest 7501 is excluded from available priests'
);

select is(
  (select count(*)::int from public.get_available_priests(
    '2026-09-10 10:30:00+02'::timestamptz,
    '2026-09-10 11:30:00+02'::timestamptz
  ) where id = 7502),
  1,
  'free priest 7502 is returned in available priests'
);

-- ------------------------------------------------- 10..16: admin_assign_priest_and_venue
-- Non-admin execution fails
set local role authenticated;
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007501"}';

select throws_ok(
  $$
    select public.admin_assign_priest_and_venue(
      'bbbbbbbb-7501-0000-0000-000000000001'::uuid,
      'cccccccc-7501-0000-0000-000000000001'::uuid,
      7501
    );
  $$,
  '42501',
  null,
  'non-admin caller cannot invoke admin_assign_priest_and_venue'
);
reset role;

-- Admin happy path assignment
set local role authenticated;
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007502"}';

select lives_ok(
  $$
    select public.admin_assign_priest_and_venue(
      'bbbbbbbb-7501-0000-0000-000000000001'::uuid,
      'cccccccc-7501-0000-0000-000000000001'::uuid,
      7501,
      'تم تأكيد الحجز وإسناد الأب الكاهن والقاعة'
    );
  $$,
  'admin successfully assigns priest and venue'
);

select is(
  (select status::text from public.event_bookings where id = 'bbbbbbbb-7501-0000-0000-000000000001'::uuid),
  'CONFIRMED',
  'event booking status advanced to CONFIRMED'
);

select is(
  (select assigned_priest_id from public.event_bookings where id = 'bbbbbbbb-7501-0000-0000-000000000001'::uuid),
  7501::bigint,
  'event booking assigned_priest_id updated'
);

select is(
  (select assigned_venue_id from public.event_bookings where id = 'bbbbbbbb-7501-0000-0000-000000000001'::uuid),
  'cccccccc-7501-0000-0000-000000000001'::uuid,
  'event booking assigned_venue_id updated'
);

-- Conflicting venue assignment on overlapping booking fails
select throws_ok(
  $$
    select public.admin_assign_priest_and_venue(
      'bbbbbbbb-7502-0000-0000-000000000002'::uuid,
      'cccccccc-7501-0000-0000-000000000001'::uuid, -- Venue 7501 is already taken 18:00-20:00
      7502
    );
  $$,
  'P0001',
  null,
  'assigning occupied venue throws VENUE_ALREADY_BOOKED'
);

-- Conflicting priest assignment on overlapping booking fails
select throws_ok(
  $$
    select public.admin_assign_priest_and_venue(
      'bbbbbbbb-7502-0000-0000-000000000002'::uuid,
      'cccccccc-7502-0000-0000-000000000002'::uuid,
      7501 -- Priest 7501 is already assigned 18:00-20:00
    );
  $$,
  'P0001',
  null,
  'assigning busy priest throws PRIEST_ALREADY_ASSIGNED'
);
reset role;

-- ------------------------------------------------- 17..19: GiST on event_bookings & Outbox / Schedule
-- Direct insert of conflicting assigned priest throws GiST exclusion violation
select throws_ok(
  $$
    insert into public.event_bookings (
      customer_id, event_type_id, assigned_priest_id, start_time, end_time, status, tenant_id
    ) values (
      'ffffffff-0000-0000-0000-000000007501'::uuid,
      'aaaaaaaa-7501-0000-0000-000000000001'::uuid,
      7501,
      '2026-09-10 19:00:00+02'::timestamptz,
      '2026-09-10 21:00:00+02'::timestamptz,
      'CONFIRMED',
      1
    );
  $$,
  '23P01',
  null,
  'direct insert with overlapping assigned priest throws exclusion_violation 23P01'
);

select is(
  (select count(*)::int from public.priest_schedules where booking_id = 'bbbbbbbb-7501-0000-0000-000000000001'::uuid and priest_id = 7501),
  1,
  'priest schedule entry linked to booking created'
);

select is(
  (select count(*)::int from public.event_outbox where handler_type = 'WHATSAPP' and payload->>'template_name' = 'event_booking_confirmed'),
  1,
  'WhatsApp confirmation outbox event queued'
);

rollback;
