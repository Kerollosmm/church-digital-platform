-- 0024: transition engine + active_booking_count
do $$
declare
  v_user uuid; v_admin uuid; v_other_u uuid; v_slot bigint; v_book bigint; v_other_book bigint;
  v_n int; v_res public.bookings; v_old_audit int;
begin
  -- fixtures
  insert into public.users (id, phone, name, role, tenant_id)
  values ('00000000-0000-0000-0000-000000000001', '+201000000001', 'parishioner', 'PARISHIONER', 1);
  insert into public.users (id, phone, name, role, tenant_id)
  values ('00000000-0000-0000-0000-000000000002', '+201000000002', 'admin', 'ADMIN', 1);
  insert into public.users (id, phone, name, role, tenant_id)
  values ('00000000-0000-0000-0000-000000000003', '+201000000003', 'other', 'PARISHIONER', 1);
  insert into public.service_slots (service_id, starts_at, ends_at, capacity, price, status, tenant_id)
  select id, now() + interval '2 days', now() + interval '2 days 1 hour', 2, 50, 'OPEN', 1
  from public.services limit 1
  returning id into v_slot;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000001', 'role', 'authenticated')::text, true);
  select id into v_book from public.book_slot(v_slot, true);

  -- 1. count helper: 1 active with live lock
  select public.active_booking_count(v_slot) into v_n;
  if v_n <> 1 then raise exception 'FAIL: active_booking_count must be 1'; end if;

  -- 2. engine transition + single audit row
  v_res := public.transition_booking_status(v_book, 'AWAITING_CALL', 'apply_payment');
  if v_res.status <> 'AWAITING_CALL' then raise exception 'FAIL: engine must flip status'; end if;
  if v_res.locked_until is not null then raise exception 'FAIL: engine must clear lock outside PENDING_PAYMENT'; end if;
  select count(*) into v_n from public.audit_log
    where entity_type = 'bookings' and entity_id = v_book and action = 'apply_payment';
  if v_n <> 1 then raise exception 'FAIL: exactly one audit row (no trigger double-write)'; end if;

  -- 3. no-op transition: no new audit row
  v_old_audit := v_n;
  v_res := public.transition_booking_status(v_book, 'AWAITING_CALL', 'apply_payment');
  select count(*) into v_n from public.audit_log
    where entity_type = 'bookings' and entity_id = v_book and action = 'apply_payment';
  if v_n <> v_old_audit then raise exception 'FAIL: no-op must not audit'; end if;

  -- 4. engine drops the old bookings audit trigger (single-writer proof)
  if exists (select 1 from pg_trigger where tgname = 'trg_bookings_audit' and tgrelid = 'public.bookings'::regclass)
  then raise exception 'FAIL: trg_bookings_audit must be dropped'; end if;

  -- 5. ownership gate: another parishioner cannot touch the booking (admins may, legacy behavior)
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000003', 'role', 'authenticated')::text, true);
  begin
    v_res := public.transition_booking_status(v_book, 'CANCELLED', 'cancel_booking');
    raise exception 'FAIL: non-owner must be FORBIDDEN';
  exception when others then
    if sqlerrm not like '%FORBIDDEN%' then raise; end if;
  end;

  -- 6. parishioner cannot CONFIRM (privilege gate); admin can
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000001', 'role', 'authenticated')::text, true);
  begin
    v_res := public.transition_booking_status(v_book, 'CONFIRMED', 'confirm_booking');
    raise exception 'FAIL: parishioner must not CONFIRM';
  exception when others then
    if sqlerrm not like '%FORBIDDEN%' then raise; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000002', 'role', 'authenticated')::text, true);
  v_res := public.transition_booking_status(v_book, 'CONFIRMED', 'confirm_booking');
  if v_res.status <> 'CONFIRMED' then raise exception 'FAIL: admin must CONFIRM'; end if;

  -- 7. invalid transition still rejected by bookings_status_guard (0008)
  begin
    v_res := public.transition_booking_status(v_book, 'PENDING_PAYMENT', 'revert');
    raise exception 'FAIL: CONFIRMED->PENDING_PAYMENT must be rejected by the guard';
  exception when others then
    if sqlerrm not like '%INVALID_STATUS_TRANSITION%' then raise; end if;
  end;
  perform public.transition_booking_status(v_book, 'COMPLETED', 'complete_booking');

  -- 8. unknown booking
  begin
    v_res := public.transition_booking_status(999999999, 'CANCELLED', 'x');
    raise exception 'FAIL: unknown booking must raise';
  exception when others then
    if sqlerrm not like '%BOOKING_NOT_FOUND%' then raise; end if;
  end;

  -- 9. count helper unguarded variant + expired lock
  insert into public.bookings (slot_id, user_id, status, locked_until, created_by, tenant_id)
  values (v_slot, '00000000-0000-0000-0000-000000000002', 'PENDING_PAYMENT', now() - interval '1 minute', 'system', 1)
  returning id into v_other_book;
  select public.active_booking_count(v_slot) into v_n;
  if v_n <> 0 then raise exception 'FAIL: guarded count must skip expired lock (and completed bookings)'; end if;
  select public.active_booking_count(v_slot, true) into v_n;
  if v_n <> 1 then raise exception 'FAIL: unguarded count must include expired lock'; end if;

  raise notice 'OK';
end $$;
