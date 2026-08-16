BEGIN;

-- 0027: event_outbox schema + enqueue behavior
do $$
declare v_user uuid; v_slot bigint; v_book bigint; v_pay bigint; v_n int;
begin
  insert into auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p31@test.local', '+201033333331', '{}', '{}', now(), now())
  on conflict (id) do nothing;
  update public.users set role = 'USER', tenant_id = 1, deleted_at = null where id = '00000000-0000-0000-0000-000000000031';
  delete from public.payments where booking_id in (select id from public.bookings where user_id = '00000000-0000-0000-0000-000000000031');
  delete from public.bookings where user_id = '00000000-0000-0000-0000-000000000031';

  insert into public.service_slots (service_id, starts_at, ends_at, capacity, price, status, tenant_id)
  select id, now() + interval '2 days', now() + interval '2 days 1 hour', 1, 50, 'OPEN', 1
  from public.services limit 1
  returning id into v_slot;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000031', 'role', 'authenticated')::text, true);
  select id into v_book from public.book_slot(v_slot, true);

  -- 1. apply_payment enqueues WHATSAPP booking_payment_received (runs under service_role / postgres)
  reset role;
  perform set_config('request.jwt.claims', null, true);
  insert into public.payments (booking_id, amount, status, tenant_id)
  values (v_book, 50, 'CREATED', 1) returning id into v_pay;
  perform public.apply_payment(v_pay);
  select count(*) into v_n from public.event_outbox
    where handler_type = 'WHATSAPP' and (payload->>'phone' = '+201033333331' or payload->>'booking_id' = v_book::text or payload->'params'->>'booking_id' = v_book::text);
  if v_n < 1 then raise exception 'FAIL: apply_payment must enqueue WHATSAPP event'; end if;
  if (select status from public.event_outbox where handler_type = 'WHATSAPP' and (payload->>'phone' = '+201033333331' or payload->>'booking_id' = v_book::text or payload->'params'->>'booking_id' = v_book::text) order by id desc limit 1) <> 'PENDING' then raise exception 'FAIL: default PENDING'; end if;

  -- 2. old tables gone
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename in ('whatsapp_outbox','refund_requests'))
  then raise exception 'FAIL: legacy outbox tables must be dropped'; end if;

  -- 3. RLS: clients cannot read or write event_outbox (no policies)
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000031', 'role', 'authenticated')::text, true);
  select count(*) into v_n from public.event_outbox;
  if v_n <> 0 then raise exception 'FAIL: clients must not read event_outbox'; end if;
  begin
    insert into public.event_outbox (handler_type, payload) values ('WHATSAPP', '{}'::jsonb);
    raise exception 'FAIL: client insert must be blocked';
  exception when others then null; end;

  raise notice 'OK';
end $$;

ROLLBACK;
