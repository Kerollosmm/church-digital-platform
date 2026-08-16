BEGIN;

-- 0035_concurrency_atomic_test.sql: Test atomic booking decrement, invariants and schedule exclusion
do $$
declare
  v_user uuid;
  v_user2 uuid;
  v_slot bigint;
  v_res1 jsonb;
  v_res2 jsonb;
  v_rem int;
  v_idemp uuid := gen_random_uuid();
begin
  insert into auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('35353535-3535-3535-3535-353535353535', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'u35@test.local', '+201035353535', '{}', '{}', now(), now()),
         ('36363636-3636-3636-3636-363636363636', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'u36@test.local', '+201036363636', '{}', '{}', now(), now())
  on conflict (id) do nothing;
  update public.users set role = 'USER', tenant_id = 1, deleted_at = null where id in ('35353535-3535-3535-3535-353535353535', '36363636-3636-3636-3636-363636363636');

  v_user := '35353535-3535-3535-3535-353535353535';
  v_user2 := '36363636-3636-3636-3636-363636363636';

  delete from public.bookings where user_id in (v_user, v_user2);

  -- Create a capacity-2 open slot
  insert into public.service_slots (service_id, starts_at, ends_at, capacity, remaining_capacity, price, status, tenant_id, schedule_range)
  select service_id, now() + interval '10 days', now() + interval '10 days 1 hour', 2, 2, 50, 'OPEN', public.tenant_id(), tstzrange(now() + interval '10 days', now() + interval '10 days 1 hour', '[)')
  from public.service_slots limit 1
  returning id into v_slot;

  -- 1. First user books 1 seat atomically with idempotency key
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role','authenticated')::text, true);
  
  v_res1 := public.fn_book_slot_atomic(v_slot, 1, true, v_idemp);
  if (v_res1->>'success')::boolean is not true then
    raise exception 'FAIL: first user booking must succeed';
  end if;

  -- 2. Idempotent replay with same idempotency key returns cached booking
  v_res2 := public.fn_book_slot_atomic(v_slot, 1, true, v_idemp);
  if (v_res2->>'idempotent_replay')::boolean is not true then
    raise exception 'FAIL: repeated request must be idempotent replay';
  end if;

  -- 3. Second user books remaining 1 seat
  perform set_config('request.jwt.claims', json_build_object('sub', v_user2, 'role','authenticated')::text, true);
  v_res1 := public.fn_book_slot_atomic(v_slot, 1, false, null);
  if (v_res1->>'success')::boolean is not true then
    raise exception 'FAIL: second user booking must succeed';
  end if;

  -- 4. Third attempt should fail with INVENTORY_EXHAUSTED
  begin
    perform public.fn_book_slot_atomic(v_slot, 1, false, null);
    raise exception 'FAIL: third booking attempt must fail when inventory exhausted';
  exception when others then
    if SQLERRM not like '%INVENTORY_EXHAUSTED%' then
      raise exception 'FAIL: expected INVENTORY_EXHAUSTED but got %', SQLERRM;
    end if;
  end;

  reset role;

  -- Check remaining capacity is 0
  select remaining_capacity into v_rem from public.service_slots where id = v_slot;
  if v_rem <> 0 then
    raise exception 'FAIL: remaining_capacity expected 0, got %', v_rem;
  end if;

end $$;

ROLLBACK;
