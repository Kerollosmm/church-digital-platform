-- 0007: availability view. Capacity-aware (multi-seat Mass slots and single-seat
-- funeral slots both work). The lock is NOT a unique index: book_slot() serializes
-- on the service_slots row via SELECT ... FOR UPDATE, then counts active bookings
-- against capacity (see 0008). This view only reports availability.

drop view if exists public.v_available_slots;
create view public.v_available_slots with (security_invoker = true) as
with active as (
  select slot_id, count(*) as active_count
  from public.bookings
  where status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED')
    and (status <> 'PENDING_PAYMENT' or locked_until > now())
  group by slot_id
)
select s.id as slot_id, s.service_id, sv.title_ar, s.starts_at, s.ends_at,
       s.capacity, s.price, s.location,
       coalesce(a.active_count, 0) as booked_count,
       greatest(s.capacity - coalesce(a.active_count, 0), 0) as available_seats,
       case
         when s.status = 'CLOSED' then 'CLOSED'
         when s.starts_at <= now() then 'CLOSED'
         when coalesce(a.active_count, 0) >= s.capacity then 'BOOKED'
         else 'AVAILABLE'
       end as slot_status
from public.service_slots s
join public.services sv on sv.id = s.service_id
left join active a on a.slot_id = s.id
where s.tenant_id = public.tenant_id();
