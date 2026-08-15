do $$
declare v_user uuid; v_slot bigint; v_book bigint; v_pay bigint; v_pay2 bigint;
begin
  select id into v_user from public.users where role='PARISHIONER' order by id limit 1;
  select id into v_slot from public.service_slots where status <> 'CLOSED' and starts_at > now()
    and id not in (select slot_id from public.bookings where status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED')) limit 1;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role','authenticated')::text, true);
  select id into v_book from public.book_slot(v_slot, true);

  -- edge function inserts payment under service_role / postgres
  reset role;
  insert into public.payments (booking_id, amount, status, gateway_ref, merchant_order_id, tenant_id)
  values (v_book, 50, 'CREATED', null, 'order-1', public.tenant_id()) returning id into v_pay;
  -- apply_payment is service-role only (webhook edge fn)
  perform public.apply_payment(v_pay);
  if (select status from public.bookings where id = v_book) <> 'AWAITING_CALL'
  then raise exception 'FAIL: booking must transition to AWAITING_CALL'; end if;
  if (select status from public.payments where id = v_pay) <> 'PAID'
  then raise exception 'FAIL: payment must be marked PAID'; end if;
  if not exists (select 1 from public.event_outbox where handler_type = 'WHATSAPP' and payload->>'phone' = (select phone from public.users where id = v_user))
  then raise exception 'FAIL: apply_payment must enqueue a whatsapp outbox row'; end if;
  -- idempotent: second call must not error and must not duplicate the outbox row
  perform public.apply_payment(v_pay);
  if (select count(*) from public.event_outbox where handler_type = 'WHATSAPP' and (payload->>'booking_id' = v_book::text or payload->'params'->>'booking_id' = v_book::text)) <> 1
  then raise exception 'FAIL: apply_payment must be idempotent (no duplicate outbox rows)'; end if;

  -- late-webhook race: webhook arrives AFTER the slot was lost (booking cancelled / lock expired) -> money must be auto-refunded, seat must NOT be granted
  begin
    insert into public.payments (booking_id, amount, status, gateway_ref, merchant_order_id, tenant_id)
    values (v_book, 50, 'CREATED', null, 'order-2', public.tenant_id()) returning id into v_pay2;
    update public.bookings set status = 'CANCELLED', locked_until = null where id = v_book;  -- simulate lock expiry + cancel
    perform public.apply_payment(v_pay2);
    if (select status from public.payments where id = v_pay2) <> 'REFUND_PENDING'
    then raise exception 'FAIL: late webhook must set REFUND_PENDING'; end if;
    if (select status from public.bookings where id = v_book) <> 'CANCELLED'
    then raise exception 'FAIL: late webhook must not revive a cancelled booking'; end if;
    if not exists (select 1 from public.event_outbox where handler_type = 'PAYMOB_REFUND' and payload->>'payment_id' = v_pay2::text)
    then raise exception 'FAIL: late webhook must enqueue a refund request'; end if;
  end;
end $$;
