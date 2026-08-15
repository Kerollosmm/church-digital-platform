-- 0024: single-writer transition engine + availability count helper.
-- Rule (conventions.md): booking status changes ONLY via transition_booking_status.
create or replace function public.active_booking_count(
  p_slot_id bigint,
  p_include_expired_locks boolean default false
) returns int language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.bookings
  where slot_id = p_slot_id
    and status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED')
    and (p_include_expired_locks
         or status <> 'PENDING_PAYMENT'
         or locked_until > now())
$$;

create or replace function public.transition_booking_status(
  p_booking_id bigint,
  p_new_status public.booking_status,
  p_action text,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
) returns public.bookings language plpgsql security definer set search_path = public as $$
declare
  v_book public.bookings;
  v_old_status public.booking_status;
  v_role text := public.current_user_role();
begin
  select * into v_book from public.bookings where id = p_booking_id for update;
  if v_book is null then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_book.status = p_new_status then return v_book; end if;

  -- SECURITY DEFINER must never widen access: re-assert gates here.
  if v_role not in ('ADMIN','PRIEST','SUPER_ADMIN') and v_book.user_id <> auth.uid()
  then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
  -- Regular users can only cancel their own bookings
  if v_role not in ('ADMIN','PRIEST','SUPER_ADMIN') then
    if p_new_status not in ('CANCELLED') then
      raise exception 'FORBIDDEN: users can only cancel bookings' using errcode = '42501';
    end if;
  end if;

  v_old_status := v_book.status;
  update public.bookings
     set status = p_new_status,
         locked_until = case when p_new_status = 'PENDING_PAYMENT' then locked_until else null end,
         updated_at = now()
   where id = p_booking_id
   returning * into v_book;

  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (auth.uid(), p_action, 'bookings', p_booking_id,
          jsonb_build_object('old_status', v_old_status, 'new_status', p_new_status,
                             'reason', p_reason, 'slot_id', v_book.slot_id) || p_metadata);
  return v_book;
end $$;

-- bookings audit is engine-owned now; payments + complaints triggers stay.
drop trigger if exists trg_bookings_audit on public.bookings;

grant execute on function public.transition_booking_status(bigint, public.booking_status, text, text, jsonb) to authenticated, service_role;
grant execute on function public.active_booking_count(bigint, boolean) to authenticated, service_role;

drop view if exists public.v_available_slots;
create view public.v_available_slots with (security_invoker = true) as
select s.id as slot_id, s.service_id, sv.title_ar, s.starts_at, s.ends_at,
       s.capacity, s.price, s.location,
       public.active_booking_count(s.id) as booked_count,
       greatest(s.capacity - public.active_booking_count(s.id), 0) as available_seats,
       case
         when s.status = 'CLOSED' then 'CLOSED'
         when s.starts_at <= now() then 'CLOSED'
         when public.active_booking_count(s.id) >= s.capacity then 'BOOKED'
         else 'AVAILABLE'
       end as slot_status
from public.service_slots s
join public.services sv on sv.id = s.service_id
where s.tenant_id = public.tenant_id();

drop view if exists public.v_schedule_today;
create view public.v_schedule_today with (security_invoker = true) as
select sl.id as slot_id, s.title_ar, sl.starts_at, sl.ends_at, sl.location,
       case when public.active_booking_count(sl.id) > 0 then 'BOOKED' else 'AVAILABLE' end as display_status
from public.service_slots sl
join public.services s on s.id = sl.service_id
where sl.starts_at >= date_trunc('day', now())
  and sl.starts_at <  date_trunc('day', now()) + interval '1 day'
  and sl.status <> 'CLOSED'
  and sl.tenant_id = public.tenant_id()
order by sl.starts_at;
