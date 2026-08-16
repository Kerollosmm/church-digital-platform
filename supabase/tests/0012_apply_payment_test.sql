BEGIN;

do $$
declare v_user uuid; v_slot bigint; v_book bigint; v_pay bigint; v_pay2 bigint;
begin
  insert into auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('12121212-1212-1212-1212-121212121212', '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', 'user-pay12@test.local', '+201000000012', '{}', '{"name":"Pay User 12"}', now(), now())
  on conflict (id) do nothing;
  update public.users set role = 'USER', tenant_id = 1, deleted_at = null where id = '12121212-1212-1212-1212-121212121212';
  v_user := '12121212-1212-1212-1212-121212121212';
  delete from public.payments where booking_id in (select id from public.bookings where user_id = v_user);
  delete from public.bookings where user_id = v_user;
  insert into public.services (id, title_ar, tenant_id) overriding system value values (99912, 'خدمة 012', 1) on conflict do nothing;
  insert into public.service_slots (id, service_id, starts_at, ends_at, capacity, remaining_capacity, price, status, tenant_id)
  overriding system value
  values (999121, 99912, now() + interval '8 days', now() + interval '8 days 1 hour', 1, 1, 50, 'OPEN', 1)
  on conflict (id) do update set starts_at = now() + interval '8 days', capacity = 1, remaining_capacity = 1, status = 'OPEN';
  v_slot := 999121;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role','authenticated')::text, true);
  select id into v_book from public.book_slot(v_slot, true);

  -- edge function inserts payment under service_role / postgres
  reset role;
  perform set_config('request.jwt.claims', null, true);
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

ROLLBACK;
