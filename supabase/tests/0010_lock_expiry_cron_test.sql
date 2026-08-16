do $$
declare v_user uuid; v_wait uuid; v_slot bigint; v_book bigint;
begin
  insert into auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('66666666-6666-6666-6666-666666666666', '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', 'user-exp1@test.local', '+201000000071', '{}', '{"name":"Exp User 1"}', now(), now()),
         ('77777777-7777-7777-7777-777777777777', '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', 'user-exp2@test.local', '+201000000072', '{}', '{"name":"Exp User 2"}', now(), now())
  on conflict (id) do nothing;
  update public.users set role = 'USER', tenant_id = 1, deleted_at = null where id in ('66666666-6666-6666-6666-666666666666', '77777777-7777-7777-7777-777777777777');

  v_user := '66666666-6666-6666-6666-666666666666';
  v_wait := '77777777-7777-7777-7777-777777777777';

  delete from public.bookings where user_id in (v_user, v_wait);
  delete from public.waiting_list where user_id in (v_user, v_wait);

  insert into public.services (id, title_ar, tenant_id) overriding system value values (99910, 'خدمة 010', 1) on conflict do nothing;

  insert into public.service_slots (id, service_id, starts_at, ends_at, capacity, remaining_capacity, price, status, tenant_id)
  overriding system value
  values (999101, 99910, now() + interval '7 days', now() + interval '7 days 1 hour', 1, 1, 0, 'OPEN', 1)
  on conflict (id) do update set starts_at = now() + interval '7 days', capacity = 1, remaining_capacity = 1, status = 'OPEN';
  v_slot := 999101;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role','authenticated')::text, true);
  select id into v_book from public.book_slot(v_slot, false);

  -- another parishioner joins waiting list for the same slot
  perform set_config('request.jwt.claims', json_build_object('sub', v_wait, 'role','authenticated')::text, true);
  perform public.join_waiting_list(v_slot);

  -- age the lock so it is expired
  reset role;
  perform set_config('request.jwt.claims', null, true);
  update public.bookings set locked_until = now() - interval '1 minute' where id = v_book;

  -- run the same body the cron job runs
  perform public.expire_stale_bookings();
  if (select status from public.bookings where id = v_book) <> 'CANCELLED'
  then raise exception 'FAIL: expired lock must be cancelled by expire_stale_bookings()'; end if;

  -- waiting-list promotion: the WAITING user gets a new PENDING_PAYMENT booking (10-min take-it window)
  if not exists (
    select 1 from public.bookings b
    where b.slot_id = v_slot and b.user_id = v_wait and b.status = 'PENDING_PAYMENT'
      and b.locked_until > now() + interval '9 minutes'
  ) then raise exception 'FAIL: waiting list must be promoted after expiry with 10-min window'; end if;
  if not exists (select 1 from public.waiting_list where slot_id = v_slot and user_id = v_wait and status = 'OFFERED')
  then raise exception 'FAIL: waiting list row must be marked OFFERED'; end if;
end $$;
do $$
begin
  if not exists (select 1 from cron.job where jobname = 'expire-bookings')
  then raise exception 'FAIL: cron job expire-bookings must be scheduled'; end if;
end $$;
