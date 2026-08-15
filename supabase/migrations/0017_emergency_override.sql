-- 0017: priest Emergency Override — reschedule + apology + refund request

create or replace function public.emergency_override(
  p_booking_id bigint,
  p_new_slot_id bigint,
  p_refund boolean default false
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.current_user_role();
  v_book public.bookings;
  v_phone text;
  v_new public.bookings;
  v_slot_new public.service_slots;
  v_paid numeric(10,2) := 0;
begin
  if v_role not in ('PRIEST','ADMIN','SUPER_ADMIN') then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
  select * into v_book from public.bookings where id = p_booking_id for update;
  if v_book is null then raise exception 'BOOKING_NOT_FOUND'; end if;
  if not exists (select 1 from public.service_slots where id = p_new_slot_id and status <> 'CLOSED' and starts_at > now())
  then raise exception 'SLOT_UNAVAILABLE'; end if;
  select phone into v_phone from public.users where id = v_book.user_id;
  perform public.transition_booking_status(p_booking_id, 'RESCHEDULED', 'emergency_reschedule', null, jsonb_build_object('new_slot_id', p_new_slot_id, 'refund', p_refund));
  begin
    -- capacity-aware reschedule: lock the target slot and count active bookings
    select * into v_slot_new from public.service_slots where id = p_new_slot_id for update;
    if v_slot_new is null or v_slot_new.status = 'CLOSED' then raise exception 'NEW_SLOT_TAKEN'; end if;
    if public.active_booking_count(p_new_slot_id, true) >= v_slot_new.capacity then raise exception 'NEW_SLOT_TAKEN'; end if;
    insert into public.bookings (slot_id, user_id, status, created_by, notes, tenant_id)
    values (p_new_slot_id, v_book.user_id, 'CONFIRMED', 'employee', 'rescheduled by emergency_override', public.tenant_id())
    returning * into v_new;
  end;
  if v_phone is not null then
    insert into public.event_outbox (handler_type, payload)
    values ('WHATSAPP', jsonb_build_object('phone', v_phone, 'template_name', 'booking_apology', 'params', jsonb_build_object('booking_id', p_booking_id)));
    insert into public.event_outbox (handler_type, payload)
    values ('WHATSAPP', jsonb_build_object('phone', v_phone, 'template_name', 'booking_rescheduled',
                                           'params', jsonb_build_object('old_slot', v_book.slot_id, 'new_slot', p_new_slot_id)));
  end if;
  if p_refund then
    select coalesce(sum(amount), 0) into v_paid from public.payments
    where booking_id = p_booking_id and status = 'PAID';
    if v_paid > 0 then
      insert into public.event_outbox (handler_type, payload)
      select 'PAYMOB_REFUND', jsonb_build_object('payment_id', id, 'amount', amount)
      from public.payments
      where booking_id = p_booking_id and status = 'PAID'
      and not exists (select 1 from public.event_outbox where handler_type = 'PAYMOB_REFUND' and payload->>'payment_id' = payments.id::text);
    end if;
  end if;
  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (auth.uid(), 'emergency_override', 'bookings', p_booking_id,
          jsonb_build_object('new_booking_id', v_new.id, 'new_slot_id', p_new_slot_id, 'refund', p_refund));
  return v_new.id;
end $$;
