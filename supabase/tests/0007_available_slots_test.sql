do $$
declare v int; v_user uuid;
begin
  if not exists (select 1 from public.v_available_slots) then
    raise exception 'FAIL: view must exist and return rows';
  end if;
  select count(*) into v from public.v_available_slots where slot_status = 'BOOKED';
  if v < 1 then raise exception 'FAIL: expected at least one BOOKED slot (seed created one)'; end if;
  select count(*) into v from public.v_available_slots where slot_status = 'AVAILABLE';
  if v < 1 then raise exception 'FAIL: expected at least one AVAILABLE slot (seed created one)'; end if;
  select count(*) into v from public.v_available_slots where available_seats = 9;
  if v < 1 then raise exception 'FAIL: expected a slot with 9 available seats'; end if;

  -- parishioner regression test: RLS on bookings must not hide booked slots from parishioners viewing v_available_slots
  select id into v_user from public.users where role = 'PARISHIONER' limit 1;
  if v_user is null then raise exception 'FAIL: seed must contain a PARISHIONER'; end if;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  select count(*) into v from public.v_available_slots where slot_status = 'BOOKED';
  if v < 1 then raise exception 'FAIL: parishioner must see TRUE booked slot status via v_available_slots'; end if;
end $$;
