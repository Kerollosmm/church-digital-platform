-- 0005: complaints. body_encrypted is NEVER readable via PostgREST:
-- users read only v_my_complaints / admins read only v_complaints (no body column).
create table if not exists public.complaints (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  category text not null,
  body_encrypted bytea not null,
  status public.complaint_status not null default 'NEW',
  assigned_to uuid,
  tenant_id bigint not null default public.tenant_id(),
  created_at timestamptz not null default now()
);
alter table public.complaints enable row level security;
drop policy if exists "complaints deny table access" on public.complaints;
create policy "complaints deny table access" on public.complaints for select using (false);

drop view if exists public.v_my_complaints;
create view public.v_my_complaints with (security_invoker = true) as
select id, category, status, assigned_to, created_at
from public.complaints
where user_id = auth.uid() and tenant_id = public.tenant_id();

drop view if exists public.v_complaints;
create view public.v_complaints with (security_invoker = true) as
select id, user_id, category, status, assigned_to, created_at
from public.complaints
where public.is_admin_or_priest()
  and (assigned_to = auth.uid() or public.is_admin())
  and tenant_id = public.tenant_id();

drop policy if exists "complaints assign write" on public.complaints;
drop policy if exists "complaints_admin_assign" on public.complaints;
create policy "complaints_admin_assign" on public.complaints for update to authenticated
  using (public.is_admin() and tenant_id = public.tenant_id())
  with check (
    public.is_admin()
    and tenant_id = public.tenant_id()
    and (assigned_to is null or assigned_to <> auth.uid())
  );
