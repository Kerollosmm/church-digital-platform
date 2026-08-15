-- 0015: manual booking mode (cash, by employee) — opt-in recorded per A9
create or replace function public.manual_book(
  p_slot_id bigint,
  p_phone text,
  p_opt_in boolean default false,
  p_notes text default null
) returns public.bookings language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.current_user_role();
  v_user uuid;
  v_book public.bookings;
  v_slot public.service_slots;
  v_notes text;
begin
  if v_role not in ('ADMIN','PRIEST','SUPER_ADMIN') then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
  select id into v_user from public.users where phone = p_phone;
  if v_user is null then raise exception 'USER_NOT_FOUND'; end if;
  if not exists (select 1 from public.service_slots where id = p_slot_id and status <> 'CLOSED' and starts_at > now())
  then raise exception 'SLOT_UNAVAILABLE'; end if;
  if p_opt_in then
    insert into public.whatsapp_optins (phone, source) values (p_phone, 'MANUAL')
    on conflict (phone) do update set consented_at = now();
  end if;
  begin
    -- capacity-aware (same semantics as book_slot)
    select * into v_slot from public.service_slots where id = p_slot_id for update;
    if v_slot is null or v_slot.status = 'CLOSED' then raise exception 'SLOT_TAKEN'; end if;
    if public.active_booking_count(p_slot_id, true) >= v_slot.capacity then raise exception 'SLOT_TAKEN'; end if;
    insert into public.bookings (slot_id, user_id, status, paid_amount, created_by, notes, tenant_id)
    values (p_slot_id, v_user, 'CONFIRMED', v_slot.price, 'employee', coalesce(p_notes, 'manual'), public.tenant_id())
    returning * into v_book;
  end;
  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (auth.uid(), 'manual_book', 'bookings', v_book.id,
          jsonb_build_object('slot_id', p_slot_id, 'phone', p_phone, 'opt_in', p_opt_in));
  return v_book;
end $$;
