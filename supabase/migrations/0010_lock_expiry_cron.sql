-- 0010: every minute, expire PENDING_PAYMENT locks, cancel, promote waiting list
create or replace function public.expire_stale_bookings() returns int
language plpgsql security definer set search_path = public as $$
declare
  r record;
  n int := 0;
begin
  for r in
    select id, slot_id from public.bookings
    where status = 'PENDING_PAYMENT' and locked_until < now()
  loop
    perform public.transition_booking_status(r.id, 'CANCELLED', 'expire_lock', 'stale payment lock', jsonb_build_object('slot_id', r.slot_id));
    perform public.promote_waiting_list(r.slot_id);
    n := n + 1;
  end loop;
  return n;
end $$;

select cron.schedule('expire-bookings', '* * * * *',
  $$ select public.expire_stale_bookings(); $$);
