do $$
declare v_user uuid; v_slot bigint; v_book bigint; v_id bigint;
       v_slot2 bigint; v_user2 uuid; v_book2 bigint; v_third bigint;
begin
  select id into v_user from public.users where role = 'PARISHIONER' limit 1;
  if v_user is null then raise exception 'FAIL: seed must contain a PARISHIONER'; end if;
  select id into v_slot from public.service_slots where status <> 'CLOSED' and starts_at > now() and capacity = 1 limit 1;

  -- multi-seat fixture (created as postgres: RLS only lets admins insert slots)
  insert into public.service_slots (service_id, starts_at, ends_at, capacity, price, status, tenant_id)
  select service_id, now() + interval '3 days', now() + interval '3 days 1 hour', 2, 50, 'OPEN', public.tenant_id()
  from public.service_slots limit 1
  returning id into v_slot2;
  select id into v_user2 from public.users where role = 'PARISHIONER' and id <> v_user limit 1;
  if v_user2 is null then raise exception 'FAIL: seed needs a second PARISHIONER'; end if;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role','authenticated')::text, true);

  -- book_slot: creates PENDING_PAYMENT with 20-min lock + records opt-in
  select id into v_book from public.book_slot(v_slot, true);
  if v_book is null then raise exception 'FAIL: book_slot must return a booking id'; end if;
  if (select status from public.bookings where id = v_book) <> 'PENDING_PAYMENT'
  then raise exception 'FAIL: new booking must be PENDING_PAYMENT'; end if;
  if (select locked_until from public.bookings where id = v_book) < now() + interval '19 minutes'
  then raise exception 'FAIL: lock must be ~20 minutes'; end if;
  if not exists (select 1 from public.whatsapp_optins where phone = (select phone from public.users where id = v_user))
  then raise exception 'FAIL: opt-in must be recorded in book_slot'; end if;

  -- same slot again → must fail (capacity=1 seed slot; FOR UPDATE + count lock)
  begin
    select id into v_id from public.book_slot(v_slot, false);
    raise exception 'FAIL: second book_slot on same slot must fail';
  exception when others then null; end;

  -- multi-seat slot: capacity=2 allows two active bookings (different users), third fails
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role','authenticated')::text, true);
  select id into v_book2 from public.book_slot(v_slot2, false);
  if v_book2 is null then raise exception 'FAIL: first seat on capacity=2 slot'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_user2, 'role','authenticated')::text, true);
  if (select id from public.book_slot(v_slot2, false)) is null
  then raise exception 'FAIL: second seat on capacity=2 slot'; end if;

  begin
    select id into v_third from public.book_slot(v_slot2, false);
    raise exception 'FAIL: third seat must be rejected (SLOT_FULL or ALREADY_BOOKED_SLOT)';
  exception when others then null; end;
  if (select count(*) from public.bookings where slot_id = v_slot2
      and status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED')) <> 2
  then raise exception 'FAIL: capacity=2 slot must hold exactly 2 active bookings'; end if;

  -- restore context for the remaining assertions
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role','authenticated')::text, true);

  -- parishioner role assertion: v_available_slots shows true booked_count/status for fully booked slot
  if not exists (select 1 from public.v_available_slots where slot_id = v_slot2 and slot_status = 'BOOKED' and booked_count = 2)
  then raise exception 'FAIL: parishioner must see slot_status BOOKED and booked_count 2 on fully booked slot'; end if;

  -- invalid transition must be rejected: PENDING_PAYMENT → CONFIRMED (needs apply_payment first)
  begin
    update public.bookings set status = 'CONFIRMED' where id = v_book;
    raise exception 'FAIL: PENDING_PAYMENT -> CONFIRMED must be rejected';
  exception when others then null; end;

  -- cancel_booking frees the slot (status CANCELLED no longer counted by book_slot)
  perform public.cancel_booking(v_book);
  if (select status from public.bookings where id = v_book) <> 'CANCELLED'
  then raise exception 'FAIL: cancel_booking must set CANCELLED'; end if;
end $$;
