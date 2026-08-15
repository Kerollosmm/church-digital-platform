-- 0028: snapshot slot price into bookings.paid_amount at booking creation & payment application
create or replace function public.book_slot(
  p_slot_id bigint,
  p_opt_in boolean default false
) returns public.bookings language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_role text := public.current_user_role();
  v_slot public.service_slots;
  v_mine int;
  v_active int;
  v_book public.bookings;
  v_phone text;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED' using errcode = '28000'; end if;
  if v_role not in ('PARISHIONER','ADMIN','PRIEST') then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
  select * into v_slot from public.service_slots where id = p_slot_id for update;
  if v_slot is null or v_slot.status = 'CLOSED' or v_slot.starts_at <= now()
  then raise exception 'SLOT_UNAVAILABLE' using errcode = 'P0001'; end if;
  select count(*) into v_mine from public.bookings
  where user_id = v_user and status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED');
  if v_mine >= 3 then raise exception 'TOO_MANY_ACTIVE_BOOKINGS' using errcode = 'P0001'; end if;
  if exists (select 1 from public.bookings
             where slot_id = p_slot_id and user_id = v_user
               and status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED'))
  then raise exception 'ALREADY_BOOKED_SLOT' using errcode = 'P0001'; end if;
  select public.active_booking_count(p_slot_id) into v_active;
  if v_active >= v_slot.capacity then raise exception 'SLOT_FULL' using errcode = 'P0001'; end if;
  if p_opt_in then
    select phone into v_phone from public.users where id = v_user;
    if v_phone is not null then
      insert into public.whatsapp_optins (phone, source) values (v_phone, 'BOOKING')
      on conflict (phone) do update set consented_at = now();
    end if;
  end if;
  insert into public.bookings (slot_id, user_id, status, paid_amount, locked_until, created_by, tenant_id)
  values (p_slot_id, v_user, 'PENDING_PAYMENT', v_slot.price, now() + interval '20 minutes', 'system', public.tenant_id())
  returning * into v_book;
  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (v_user, 'book_slot', 'bookings', v_book.id,
          jsonb_build_object('slot_id', p_slot_id, 'opt_in', p_opt_in));
  return v_book;
end $$;

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

create or replace function public.apply_payment(p_payment_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_pay public.payments;
  v_book public.bookings;
  v_phone text;
begin
  select * into v_pay from public.payments where id = p_payment_id for update;
  if v_pay is null then raise exception 'PAYMENT_NOT_FOUND'; end if;
  if v_pay.status = 'PAID' then return; end if;
  update public.payments set status = 'PAID' where id = v_pay.id;
  if v_pay.booking_id is not null then
    select * into v_book from public.bookings where id = v_pay.booking_id for update;
    if v_book is null
       or v_book.status <> 'PENDING_PAYMENT'
       or v_book.locked_until <= now() then
      update public.payments set status = 'REFUND_PENDING' where id = v_pay.id;
      if not exists (select 1 from public.event_outbox where handler_type = 'PAYMOB_REFUND' and payload->>'payment_id' = v_pay.id::text) then
        insert into public.event_outbox (handler_type, payload)
        values ('PAYMOB_REFUND', jsonb_build_object('payment_id', v_pay.id, 'amount', v_pay.amount));
      end if;
      return;
    end if;
    update public.bookings set paid_amount = v_pay.amount where id = v_book.id;
    v_book := public.transition_booking_status(v_book.id, 'AWAITING_CALL', 'apply_payment', null, jsonb_build_object('payment_id', v_pay.id));
    select phone into v_phone from public.users where id = v_book.user_id;
    if v_phone is not null and not exists (
      select 1 from public.event_outbox
      where handler_type = 'WHATSAPP'
        and (payload->>'booking_id' = v_book.id::text or payload->'params'->>'booking_id' = v_book.id::text)
        and payload->>'template_name' = 'booking_payment_received'
    ) then
      insert into public.event_outbox (handler_type, payload)
      values ('WHATSAPP', jsonb_build_object('phone', v_phone, 'template_name', 'booking_payment_received',
                                             'params', jsonb_build_object('booking_id', v_book.id, 'amount', v_pay.amount)));
    end if;
  end if;
end $$;
