BEGIN;

-- 0024: transition whitelist test
do $$
declare v_book public.bookings;
begin
  -- Cleanup fixtures if present
  delete from public.bookings where id = 901;
  delete from public.service_slots where id = 901;
  delete from public.services where id = 901;

  -- Setup: user with a pending-payment booking
  insert into auth.users (id, email, phone) values ('cccccccc-0000-0000-0000-000000000001'::uuid, 'user24_wl@test.com', '+201000000244')
  on conflict (id) do update set email = EXCLUDED.email, phone = EXCLUDED.phone;
  insert into public.users (id, phone, name, role, tenant_id)
    values ('cccccccc-0000-0000-0000-000000000001'::uuid, '+201000000244', 'User', 'USER', 1)
  on conflict (id) do update set role = 'USER', phone = EXCLUDED.phone;

  insert into public.services (id, tenant_id, title_ar)
    overriding system value
    values (901, 1, 'قداس');
  insert into public.service_slots (id, service_id, tenant_id, starts_at, ends_at, capacity)
    overriding system value
    values (901, 901, 1, now() + interval '1 day', now() + interval '1 day 2 hours', 10);
  insert into public.bookings (id, user_id, slot_id, tenant_id, status)
    overriding system value
    values (901, 'cccccccc-0000-0000-0000-000000000001'::uuid, 901, 1, 'PENDING_PAYMENT');

  set local role authenticated;
  set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000000001"}';

  -- Should be BLOCKED: user trying to skip payment
  begin
    perform public.transition_booking_status(901, 'AWAITING_CALL', 'user_skip', 'test');
    raise exception 'FAIL: user skipped payment via transition engine';
  exception when sqlstate '42501' then
    null; -- Expected: FORBIDDEN
  end;

  -- Should be ALLOWED: user cancelling own booking
  v_book := public.transition_booking_status(901, 'CANCELLED', 'user_cancel', 'changed mind');
  if v_book.status <> 'CANCELLED' then
    raise exception 'FAIL: user cancel did not work';
  end if;

  raise notice 'OK';
end $$;

ROLLBACK;
