BEGIN;

-- 0029: FCM token update RPC + FCM push outbox trigger test
do $$
declare
  v_user uuid := '00000000-0000-0000-0000-000000000029';
  v_user_no_fcm uuid := '00000000-0000-0000-0000-000000000030';
  v_slot bigint;
  v_book bigint;
  v_book2 bigint;
  v_token text;
  v_n int;
  v_payload jsonb;
begin
  -- Fixtures
  insert into auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values (v_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fcm1@test.local', '+201029292929', '{}', '{}', now(), now()),
         (v_user_no_fcm, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fcm2@test.local', '+201030303030', '{}', '{}', now(), now())
  on conflict (id) do nothing;
  update public.users set role = 'USER', tenant_id = 1, deleted_at = null, fcm_token = null where id in (v_user, v_user_no_fcm);
  delete from public.bookings where user_id in (v_user, v_user_no_fcm);

  insert into public.service_slots (service_id, starts_at, ends_at, capacity, price, status, tenant_id)
  select id, now() + interval '3 days', now() + interval '3 days 1 hour', 10, 0, 'OPEN', 1
  from public.services limit 1
  returning id into v_slot;

  -- 1. Test update_fcm_token RPC as authenticated user
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user::text, 'role', 'authenticated')::text, true);

  perform public.update_fcm_token('my_device_fcm_token_123');

  reset role;
  select fcm_token into v_token from public.users where id = v_user;
  if v_token <> 'my_device_fcm_token_123' then
    raise exception 'FAIL: update_fcm_token did not update user fcm_token';
  end if;

  -- 2. Test booking status transitions enqueue FCM_PUSH to event_outbox
  delete from public.event_outbox where handler_type = 'FCM_PUSH';

  -- Create booking as PENDING_PAYMENT -> should NOT enqueue FCM_PUSH
  insert into public.bookings (slot_id, user_id, status, tenant_id)
  values (v_slot, v_user, 'PENDING_PAYMENT', 1)
  returning id into v_book;

  select count(*) into v_n from public.event_outbox where handler_type = 'FCM_PUSH';
  if v_n <> 0 then
    raise exception 'FAIL: PENDING_PAYMENT must not enqueue FCM_PUSH';
  end if;

  -- Transition to AWAITING_CALL -> should enqueue FCM_PUSH
  update public.bookings set status = 'AWAITING_CALL' where id = v_book;

  select count(*) into v_n from public.event_outbox where handler_type = 'FCM_PUSH';
  if v_n <> 1 then
    raise exception 'FAIL: transition to AWAITING_CALL must enqueue 1 FCM_PUSH row';
  end if;

  select payload into v_payload from public.event_outbox where handler_type = 'FCM_PUSH' order by id desc limit 1;
  if v_payload->>'fcm_token' <> 'my_device_fcm_token_123' or
     v_payload->>'title' <> 'Booking Pending Confirmation' or
     v_payload->('data')->>'booking_id' <> v_book::text then
    raise exception 'FAIL: invalid FCM_PUSH payload for AWAITING_CALL: %', v_payload;
  end if;

  -- Transition to CONFIRMED -> should enqueue another FCM_PUSH
  update public.bookings set status = 'CONFIRMED' where id = v_book;

  select count(*) into v_n from public.event_outbox where handler_type = 'FCM_PUSH';
  if v_n <> 2 then
    raise exception 'FAIL: transition to CONFIRMED must enqueue 2nd FCM_PUSH row';
  end if;

  select payload into v_payload from public.event_outbox where handler_type = 'FCM_PUSH' order by id desc limit 1;
  if v_payload->>'title' <> 'Booking Confirmed' then
    raise exception 'FAIL: invalid FCM_PUSH payload for CONFIRMED: %', v_payload;
  end if;

  -- Transition to CANCELLED -> should enqueue 3rd FCM_PUSH
  update public.bookings set status = 'CANCELLED' where id = v_book;

  select count(*) into v_n from public.event_outbox where handler_type = 'FCM_PUSH';
  if v_n <> 3 then
    raise exception 'FAIL: transition to CANCELLED must enqueue 3rd FCM_PUSH row';
  end if;

  select payload into v_payload from public.event_outbox where handler_type = 'FCM_PUSH' order by id desc limit 1;
  if v_payload->>'title' <> 'Booking Cancelled' then
    raise exception 'FAIL: invalid FCM_PUSH payload for CANCELLED: %', v_payload;
  end if;

  -- 3. Test user without fcm_token -> should NOT enqueue FCM_PUSH
  insert into public.bookings (slot_id, user_id, status, tenant_id)
  values (v_slot, v_user_no_fcm, 'CONFIRMED', 1)
  returning id into v_book2;

  select count(*) into v_n from public.event_outbox where handler_type = 'FCM_PUSH';
  if v_n <> 3 then
    raise exception 'FAIL: booking for user without fcm_token must not enqueue FCM_PUSH';
  end if;

  raise notice 'FCM triggers test OK';
end $$;

ROLLBACK;
