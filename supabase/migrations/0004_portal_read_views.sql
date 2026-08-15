-- 0004: portal read views + faq table + RLS (public read, ADMIN/PRIEST write)
create table if not exists public.faq (
  id bigint generated always as identity primary key,
  question_ar text not null,
  answer_ar text not null,
  position int not null default 0,
  published boolean not null default true,
  tenant_id bigint not null default public.tenant_id()
);
alter table public.faq enable row level security;

drop policy if exists "faq public read" on public.faq;
create policy "faq public read" on public.faq for select to anon, authenticated
  using (published = true and tenant_id = public.tenant_id());
drop policy if exists "faq admin write" on public.faq;
create policy "faq admin write" on public.faq for all to authenticated
  using (public.is_admin_or_priest() and tenant_id = public.tenant_id())
  with check (public.is_admin_or_priest() and tenant_id = public.tenant_id());

drop policy if exists "services public read" on public.services;
create policy "services public read" on public.services for select to anon, authenticated
  using (tenant_id = public.tenant_id());
drop policy if exists "services admin write" on public.services;
create policy "services admin write" on public.services for all to authenticated
  using (public.is_admin_or_priest() and tenant_id = public.tenant_id())
  with check (public.is_admin_or_priest() and tenant_id = public.tenant_id());

drop policy if exists "priests public read" on public.priests;
create policy "priests public read" on public.priests for select to anon, authenticated
  using (tenant_id = public.tenant_id());
drop policy if exists "priests admin write" on public.priests;
create policy "priests admin write" on public.priests for all to authenticated
  using (public.is_admin_or_priest() and tenant_id = public.tenant_id())
  with check (public.is_admin_or_priest() and tenant_id = public.tenant_id());

drop policy if exists "service_slots public read" on public.service_slots;
create policy "service_slots public read" on public.service_slots for select to anon, authenticated
  using (tenant_id = public.tenant_id());

-- views: security_invoker so base-table RLS applies; explicit columns only (no SELECT *)
drop view if exists public.v_services;
create view public.v_services with (security_invoker = true) as
select s.id, s.title_ar, s.description, s.location,
       min(sl.starts_at) filter (where sl.status <> 'CLOSED' and sl.starts_at > now()) as next_slot_starts_at,
       min(sl.price) filter (where sl.status <> 'CLOSED' and sl.starts_at > now()) as price_from,
       s.tenant_id
from public.services s
left join public.service_slots sl on sl.service_id = s.id
where s.tenant_id = public.tenant_id()
group by s.id;

drop view if exists public.v_priests;
create view public.v_priests with (security_invoker = true) as
select id, name, photo_url, bio, visitation_hours, tenant_id
from public.priests
where tenant_id = public.tenant_id();

drop view if exists public.v_faq;
create view public.v_faq with (security_invoker = true) as
select id, question_ar, answer_ar, position
from public.faq
where published = true and tenant_id = public.tenant_id()
order by position;

drop view if exists public.v_schedule_today;
create view public.v_schedule_today with (security_invoker = true) as
select sl.id as slot_id, s.title_ar, sl.starts_at, sl.ends_at, sl.location,
       case when b.id is null then 'AVAILABLE' else 'BOOKED' end as display_status
from public.service_slots sl
join public.services s on s.id = sl.service_id
left join public.bookings b on b.slot_id = sl.id and b.status in ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED')
where sl.starts_at >= date_trunc('day', now())
  and sl.starts_at <  date_trunc('day', now()) + interval '1 day'
  and sl.status <> 'CLOSED'
  and sl.tenant_id = public.tenant_id()
order by sl.starts_at;
