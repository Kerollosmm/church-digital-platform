BEGIN;

do $$
declare
  v_user uuid; v_admin uuid; v_slot1 bigint; v_slot2 bigint; v_book bigint; v_pay bigint;
  v_new_book bigint;
begin
  insert into auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('17171717-1717-1717-1717-171717171717', '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', 'user-ov17@test.local', '+201000000017', '{}', '{"name":"Override User 17"}', now(), now()),
         ('18181818-1818-1818-1818-181818181818', '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', 'admin-ov18@test.local', '+201000000018', '{}', '{"name":"Override Admin 18"}', now(), now())
  on conflict (id) do nothing;
  update public.users set role = 'USER', tenant_id = 1, deleted_at = null where id = '17171717-1717-1717-1717-171717171717';
  update public.users set role = 'ADMIN', tenant_id = 1, deleted_at = null where id = '18181818-1818-1818-1818-181818181818';

  v_user := '17171717-1717-1717-1717-171717171717';
  v_admin := '18181818-1818-1818-1818-181818181818';
  delete from public.payments where booking_id in (select id from public.bookings where user_id = v_user);
  delete from public.bookings where user_id = v_user;

  insert into public.service_slots (service_id, starts_at, ends_at, capacity, price, status, tenant_id)
  select service_id, now() + interval '10 days', now() + interval '10 days 1 hour', 1, 50, 'OPEN', public.tenant_id()
  from public.service_slots limit 1
  returning id into v_slot1;

  insert into public.service_slots (service_id, starts_at, ends_at, capacity, price, status, tenant_id)
  select service_id, now() + interval '11 days', now() + interval '11 days 1 hour', 1, 50, 'OPEN', public.tenant_id()
  from public.service_slots limit 1
  returning id into v_slot2;

  -- create a PAID booking to override
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role','authenticated')::text, true);
  select id into v_book from public.book_slot(v_slot1, true);

  reset role;
  perform set_config('request.jwt.claims', null, true);
  insert into public.payments (booking_id, amount, status, gateway_ref, merchant_order_id, tenant_id)
  values (v_book, 50, 'PAID', 555, 'order-5', public.tenant_id()) returning id into v_pay;

  -- ADMIN/PRIEST overrides: old booking -> RESCHEDULED, new booking on v_slot2, apology + refund requested
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role','authenticated')::text, true);
  select public.emergency_override(v_book, v_slot2, true) into v_new_book;
  if v_new_book is null then raise exception 'FAIL: emergency_override must return new booking id'; end if;

  reset role;
  perform set_config('request.jwt.claims', null, true);
  if (select status from public.bookings where id = v_book) <> 'RESCHEDULED'
  then raise exception 'FAIL: old booking must be RESCHEDULED'; end if;
  if (select status from public.bookings where id = v_new_book) <> 'CONFIRMED'
  then raise exception 'FAIL: new booking must be CONFIRMED'; end if;
  if not exists (select 1 from public.event_outbox
                 where handler_type = 'WHATSAPP' and payload->>'template_name' = 'booking_apology'
                   and (payload->>'booking_id' = v_book::text or payload->'params'->>'booking_id' = v_book::text))
  then raise exception 'FAIL: apology template must be enqueued'; end if;
  if exists (select 1 from public.event_outbox
             where handler_type = 'PAYMOB_REFUND' and payload->>'payment_id' = v_pay::text)
  then raise exception 'FAIL: refunds are manual per ADR 0003 — override must not enqueue refund events'; end if;

  -- PARISHIONER cannot override
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role','authenticated')::text, true);
  begin
    perform public.emergency_override(v_book, v_slot2, false);
    raise exception 'FAIL: PARISHIONER must not call emergency_override';
  exception when insufficient_privilege or others then null; end;
end $$;

ROLLBACK;
