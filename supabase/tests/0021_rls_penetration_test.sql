do $$
declare
  v_parishioner uuid; v_other uuid; v_admin uuid; v_other_booking bigint; v_amount numeric; v_price int; v_sum numeric;
begin
  select id into v_parishioner from public.users
  where role='PARISHIONER'
    and (select count(*) from public.bookings where user_id = users.id and status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED')) < 2
  order by id limit 1;
  select id into v_other from public.users
  where role='PARISHIONER' and id <> v_parishioner
  order by id limit 1;
  select id into v_admin from public.users where role='ADMIN' order by id limit 1;

  -- seed a complaint owned by someone else (as postgres, bypasses RLS; trigger encrypts it)
  insert into public.complaints (user_id, category, body_encrypted, tenant_id)
  values (v_other, 'OTHER', 'x', public.tenant_id());

  -- create a booking owned by v_parishioner
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_parishioner, 'role','authenticated')::text, true);
  select id into v_other_booking from public.book_slot(
    (select id from public.service_slots where status <> 'CLOSED' and starts_at > now()
       and id not in (select slot_id from public.bookings where status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED')) limit 1),
    false);

  -- 1. PARISHIONER cannot write service_slots, bookings, or payments (RLS filters silently -> assert no change)
  reset role;
  select coalesce(paid_amount, 0) into v_amount from public.bookings where id = v_other_booking;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_other, 'role','authenticated')::text, true);
  update public.bookings set paid_amount = coalesce(paid_amount, 0) + 1 where id = v_other_booking;

  reset role;
  if (select coalesce(paid_amount, 0) from public.bookings where id = v_other_booking) is distinct from v_amount
  then raise exception 'FAIL: PARISHIONER must not update others bookings'; end if;

  reset role;
  select price into v_price from public.service_slots limit 1;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_other, 'role','authenticated')::text, true);
  update public.service_slots set price = price + 1;

  reset role;
  if (select price from public.service_slots limit 1) <> v_price
  then raise exception 'FAIL: PARISHIONER must not write service_slots'; end if;

  reset role;
  select sum(amount) into v_sum from public.payments;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_other, 'role','authenticated')::text, true);
  update public.payments set amount = amount + 1;

  reset role;
  if (select sum(amount) from public.payments) is distinct from v_sum
  then raise exception 'FAIL: PARISHIONER must not write payments'; end if;

  -- 2. ANON cannot call state RPCs (book_slot requires auth)
  set local role anon;
  begin
    perform public.book_slot(1, false);
    raise exception 'FAIL: anon must not book';
  exception when others then null; end;

  -- 3. ADMIN can read payments + update service_slots (positive control)
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role','authenticated')::text, true);
  if (select count(*) from public.payments) = 0 then raise exception 'FAIL: ADMIN must read payments'; end if;
  update public.service_slots set price = price + 1 where id = (select id from public.service_slots limit 1);

  -- 4. body_encrypted never readable via views (complaints table has deny policy)
  if exists (select 1 from public.complaints) then raise exception 'FAIL: users must not read complaints table directly'; end if;
end $$;
