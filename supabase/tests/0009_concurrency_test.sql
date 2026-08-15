-- 0009: Concurrency + lock verification test
do $$
declare
  v_user uuid; v_user2 uuid; v_slot bigint;
  v_b1 bigint; v_b2 bigint;
begin
  select id into v_user from public.users where role = 'PARISHIONER' order by id limit 1;
  select id into v_user2 from public.users where role = 'PARISHIONER' and id <> v_user order by id limit 1;

  -- Create a capacity-1 open slot
  insert into public.service_slots (service_id, starts_at, ends_at, capacity, price, status, tenant_id)
  select service_id, now() + interval '6 days', now() + interval '6 days 1 hour', 1, 0, 'OPEN', public.tenant_id()
  from public.service_slots limit 1
  returning id into v_slot;

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
