do $$
declare v_user uuid; v_slot bigint; v_book bigint; v_id bigint;
       v_slot2 bigint; v_user2 uuid; v_book2 bigint; v_book3 bigint; v_third bigint;
begin
  -- Setup deterministic users
  insert into auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', 'user-bsm1@test.local', '+201000000081', '{}', '{"name":"BSM User 1"}', now(), now()),
         ('55555555-5555-5555-5555-555555555555', '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', 'user-bsm2@test.local', '+201000000082', '{}', '{"name":"BSM User 2"}', now(), now())
  on conflict (id) do nothing;
  update public.users set role = 'USER', tenant_id = 1, deleted_at = null where id in ('44444444-4444-4444-4444-444444444444', '55555555-5555-5555-5555-555555555555');

  v_user := '44444444-4444-4444-4444-444444444444';
  v_user2 := '55555555-5555-5555-5555-555555555555';

  insert into public.services (id, title_ar, tenant_id) overriding system value values (99908, 'خدمة 008', 1) on conflict do nothing;

  insert into public.service_slots (id, service_id, starts_at, ends_at, capacity, remaining_capacity, price, status, tenant_id)
  overriding system value
  values (999081, 99908, now() + interval '2 days', now() + interval '2 days 1 hour', 1, 1, 0, 'OPEN', 1)
  on conflict (id) do update set starts_at = now() + interval '2 days', capacity = 1, remaining_capacity = 1, status = 'OPEN';
  v_slot := 999081;

  -- multi-seat fixture
  insert into public.service_slots (id, service_id, starts_at, ends_at, capacity, remaining_capacity, price, status, tenant_id)
  overriding system value
  values (999082, 99908, now() + interval '3 days', now() + interval '3 days 1 hour', 2, 2, 50, 'OPEN', 1)
  on conflict (id) do update set starts_at = now() + interval '3 days', capacity = 2, remaining_capacity = 2, status = 'OPEN';
  v_slot2 := 999082;

  -- Clean slate
  delete from public.bookings where slot_id in (v_slot, v_slot2) or user_id in (v_user, v_user2);
  delete from public.whatsapp_optins where phone in ('+201000000081', '+201000000082');

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
  select id into v_book3 from public.book_slot(v_slot2, false);
  if v_book3 is null
  then raise exception 'FAIL: second seat on capacity=2 slot'; end if;

  begin
    select id into v_third from public.book_slot(v_slot2, false);
    raise exception 'FAIL: third seat must be rejected (SLOT_FULL or ALREADY_BOOKED_SLOT)';
  exception when others then null; end;
  if public.active_booking_count(v_slot2) <> 2
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
