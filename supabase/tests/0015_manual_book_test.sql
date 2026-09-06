BEGIN;

do $$
declare v_admin uuid; v_slot bigint; v_book bigint; v_phone text;
begin
  select id into v_admin from public.users where role='ADMIN' order by id limit 1;
  select id, (select phone from public.users where role='USER' order by id limit 1) into v_slot, v_phone
  from public.service_slots where status <> 'CLOSED' and starts_at > now()
    and id not in (select slot_id from public.bookings where status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED')) order by id limit 1;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role','authenticated')::text, true);
  -- manual booking: cash collected on the spot -> CONFIRMED immediately, created_by=employee
  select id into v_book from public.manual_book(v_slot, v_phone, true);
  if v_book is null then raise exception 'FAIL: manual_book must return booking id'; end if;
  if (select status from public.bookings where id = v_book) <> 'CONFIRMED'
  then raise exception 'FAIL: manual booking must be CONFIRMED'; end if;
  if (select created_by from public.bookings where id = v_book) <> 'employee'
  then raise exception 'FAIL: manual booking created_by must be employee'; end if;
  if not exists (select 1 from public.whatsapp_optins where phone = v_phone)
  then raise exception 'FAIL: manual_book must record opt-in'; end if;
  -- PARISHIONER cannot use manual_book
  perform set_config('request.jwt.claims', json_build_object('sub', (select id from public.users where role='USER' order by id limit 1), 'role','authenticated')::text, true);
  begin
    perform public.manual_book(v_slot, v_phone, false);
    raise exception 'FAIL: PARISHIONER must not call manual_book';
  exception when insufficient_privilege or others then null; end;
end $$;

ROLLBACK;
