do $$
declare v int; v_user uuid;
begin
  -- Fixtures
  insert into auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', 'user-slot@test.local', '+201000000096', '{}', '{"name":"Slot User"}', now(), now())
  on conflict (id) do nothing;
  update public.users set role = 'USER', tenant_id = 1 where id = '33333333-3333-3333-3333-333333333333';

  insert into public.services (id, title_ar, tenant_id) overriding system value values (99907, 'خدمة الحجز', 1) on conflict do nothing;
  
  -- Slot 1: AVAILABLE with 9 seats remaining (capacity 10, 1 active booking)
  insert into public.service_slots (id, service_id, starts_at, ends_at, capacity, remaining_capacity, price, status, tenant_id)
  overriding system value
  values (999071, 99907, now() + interval '2 days', now() + interval '2 days 2 hours', 10, 9, 0, 'OPEN', 1)
  on conflict (id) do update set starts_at = now() + interval '2 days', capacity = 10, remaining_capacity = 9, status = 'OPEN';

  delete from public.bookings where id = 999071;
  insert into public.bookings (id, slot_id, user_id, status, tenant_id)
  overriding system value
  values (999071, 999071, '33333333-3333-3333-3333-333333333333', 'CONFIRMED', 1);

  -- Slot 2: BOOKED (capacity 1, 1 active booking)
  insert into public.service_slots (id, service_id, starts_at, ends_at, capacity, remaining_capacity, price, status, tenant_id)
  overriding system value
  values (999072, 99907, now() + interval '3 days', now() + interval '3 days 2 hours', 1, 0, 0, 'OPEN', 1)
  on conflict (id) do update set starts_at = now() + interval '3 days', capacity = 1, remaining_capacity = 0, status = 'OPEN';

  delete from public.bookings where id = 999072;
  insert into public.bookings (id, slot_id, user_id, status, tenant_id)
  overriding system value
  values (999072, 999072, '33333333-3333-3333-3333-333333333333', 'CONFIRMED', 1);

  if not exists (select 1 from public.v_available_slots) then
    raise exception 'FAIL: view must exist and return rows';
  end if;
  select count(*) into v from public.v_available_slots where slot_status = 'BOOKED';
  if v < 1 then raise exception 'FAIL: expected at least one BOOKED slot'; end if;
  select count(*) into v from public.v_available_slots where slot_status = 'AVAILABLE';
  if v < 1 then raise exception 'FAIL: expected at least one AVAILABLE slot'; end if;
  select count(*) into v from public.v_available_slots where available_seats = 9;
  if v < 1 then raise exception 'FAIL: expected a slot with 9 available seats'; end if;

  -- parishioner regression test: RLS on bookings must not hide booked slots from parishioners viewing v_available_slots
  v_user := '33333333-3333-3333-3333-333333333333';
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  select count(*) into v from public.v_available_slots where slot_status = 'BOOKED';
  if v < 1 then raise exception 'FAIL: parishioner must see TRUE booked slot status via v_available_slots'; end if;
end $$;
