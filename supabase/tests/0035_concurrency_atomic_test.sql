BEGIN;

-- 0035_concurrency_atomic_test.sql: Test atomic booking decrement, invariants and dynamic capacity
do $$
declare
  v_user uuid;
  v_user2 uuid;
  v_user3 uuid;
  v_slot bigint;
  v_book1 public.bookings;
  v_book2 public.bookings;
  v_book3 public.bookings;
  v_rem int;
  v_idemp uuid := gen_random_uuid();
begin
  insert into auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('35353535-3535-3535-3535-353535353535', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'u35@test.local', '+201035353535', '{}', '{}', now(), now()),
         ('36363636-3636-3636-3636-363636363636', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'u36@test.local', '+201036363636', '{}', '{}', now(), now()),
         ('37373737-3737-3737-3737-373737373737', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'u37@test.local', '+201037373737', '{}', '{}', now(), now())
  on conflict (id) do nothing;
  update public.users set role = 'USER', tenant_id = 1, deleted_at = null where id in ('35353535-3535-3535-3535-353535353535', '36363636-3636-3636-3636-363636363636', '37373737-3737-3737-3737-373737373737');

  v_user := '35353535-3535-3535-3535-353535353535';
  v_user2 := '36363636-3636-3636-3636-363636363636';
  v_user3 := '37373737-3737-3737-3737-373737373737';

  delete from public.bookings where user_id in (v_user, v_user2, v_user3);

  -- Create a capacity-2 open slot
  insert into public.service_slots (service_id, starts_at, ends_at, capacity, price, status, tenant_id, schedule_range)
  select service_id, now() + interval '10 days', now() + interval '10 days 1 hour', 2, 50, 'OPEN', public.tenant_id(), tstzrange(now() + interval '10 days', now() + interval '10 days 1 hour', '[)')
  from public.service_slots limit 1
  returning id into v_slot;

  -- 1. First user books 1 seat atomically with idempotency key
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role','authenticated')::text, true);
  
  v_book1 := public.book_slot(v_slot, true, v_idemp);
  if v_book1.id is null then
    raise exception 'FAIL: first user booking must succeed';
  end if;

  -- 2. Idempotent replay with same idempotency key returns cached booking
  v_book2 := public.book_slot(v_slot, true, v_idemp);
  if v_book2.id <> v_book1.id then
    raise exception 'FAIL: repeated request must return existing booking';
  end if;

  -- 3. Second user books remaining 1 seat
  perform set_config('request.jwt.claims', json_build_object('sub', v_user2, 'role','authenticated')::text, true);
  v_book3 := public.book_slot(v_slot, false, null);
  if v_book3.id is null then
    raise exception 'FAIL: second user booking must succeed';
  end if;

  -- 4. Third attempt from third user should fail with SLOT_FULL
  perform set_config('request.jwt.claims', json_build_object('sub', v_user3, 'role','authenticated')::text, true);
  begin
    perform public.book_slot(v_slot, false, null);
    raise exception 'FAIL: third booking attempt must fail when inventory exhausted';
  exception when others then
    if SQLERRM not like '%SLOT_FULL%' then
      raise exception 'FAIL: expected SLOT_FULL but got %', SQLERRM;
    end if;
  end;

  reset role;

  -- Check available seats via active_booking_count is 0
  select greatest(capacity - public.active_booking_count(id), 0) into v_rem from public.service_slots where id = v_slot;
  if v_rem <> 0 then
    raise exception 'FAIL: available seats expected 0, got %', v_rem;
  end if;

end $$;

ROLLBACK;
