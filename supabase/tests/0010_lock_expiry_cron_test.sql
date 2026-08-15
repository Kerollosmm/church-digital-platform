do $$
declare v_user uuid; v_wait uuid; v_slot bigint; v_book bigint;
begin
  select id into v_user from public.users where role='PARISHIONER' order by id limit 1;
  select id into v_wait from public.users where role='PARISHIONER' and id <> v_user order by id limit 1;

  insert into public.service_slots (service_id, starts_at, ends_at, capacity, price, status, tenant_id)
  select service_id, now() + interval '7 days', now() + interval '7 days 1 hour', 1, 0, 'OPEN', public.tenant_id()
  from public.service_slots limit 1
  returning id into v_slot;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role','authenticated')::text, true);
  select id into v_book from public.book_slot(v_slot, false);

  -- another parishioner joins waiting list for the same slot
  perform set_config('request.jwt.claims', json_build_object('sub', v_wait, 'role','authenticated')::text, true);
  perform public.join_waiting_list(v_slot);

  -- age the lock so it is expired
  reset role;
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
