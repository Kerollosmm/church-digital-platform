-- 0009: Concurrency + lock verification test
do $$
declare
  v_user uuid; v_user2 uuid; v_slot bigint;
  v_b1 bigint; v_b2 bigint;
begin
  insert into auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('88888888-8888-8888-8888-888888888888', '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', 'user-conc1@test.local', '+201000000061', '{}', '{"name":"Conc User 1"}', now(), now()),
         ('99999999-9999-9999-9999-999999999999', '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', 'user-conc2@test.local', '+201000000062', '{}', '{"name":"Conc User 2"}', now(), now())
  on conflict (id) do nothing;
  update public.users set role = 'USER', tenant_id = 1, deleted_at = null where id in ('88888888-8888-8888-8888-888888888888', '99999999-9999-9999-9999-999999999999');

  v_user := '88888888-8888-8888-8888-888888888888';
  v_user2 := '99999999-9999-9999-9999-999999999999';

  delete from public.bookings where user_id in (v_user, v_user2);

  insert into public.services (id, title_ar, tenant_id) overriding system value values (99909, 'خدمة 009', 1) on conflict do nothing;

  insert into public.service_slots (id, service_id, starts_at, ends_at, capacity, remaining_capacity, price, status, tenant_id)
  overriding system value
  values (999091, 99909, now() + interval '6 days', now() + interval '6 days 1 hour', 1, 1, 0, 'OPEN', 1)
  on conflict (id) do update set starts_at = now() + interval '6 days', capacity = 1, remaining_capacity = 1, status = 'OPEN';
  v_slot := 999091;

  -- First user books slot
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role','authenticated')::text, true);
  select id into v_b1 from public.book_slot(v_slot, false);
  if v_b1 is null then raise exception 'FAIL: first user must succeed booking capacity=1 slot'; end if;

  -- Second user attempts booking same capacity=1 slot → must be rejected with SLOT_FULL
  perform set_config('request.jwt.claims', json_build_object('sub', v_user2, 'role','authenticated')::text, true);
  begin
    select id into v_b2 from public.book_slot(v_slot, false);
    raise exception 'FAIL: second user must be rejected when capacity=1 slot is full';
  exception when others then
    if SQLERRM not like '%SLOT_FULL%' then
      raise exception 'FAIL: expected SLOT_FULL error but got %', SQLERRM;
    end if;
  end;

  reset role;
  if (select count(*) from public.bookings where slot_id = v_slot and status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED')) <> 1 then
    raise exception 'FAIL: capacity=1 slot must have exactly 1 winner';
  end if;
end $$;
