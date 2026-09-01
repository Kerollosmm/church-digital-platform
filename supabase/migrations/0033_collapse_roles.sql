-- 0033: Collapse roles from (PARISHIONER, PRIEST, ADMIN, SUPER_ADMIN) to (USER, ADMIN)

do $$
begin
  if not exists (select 1 from pg_type where typname = 'app_role_new') then
    create type public.app_role_new as enum ('USER', 'ADMIN');
  end if;
end $$;

-- 0. Drop policy depending on users.role column
drop policy if exists p0_admin_update_users on public.users;

-- 1. Alter public.users role column
alter table public.users alter column role drop default;

alter table public.users alter column role type public.app_role_new
  using (
    case role::text
      when 'PARISHIONER' then 'USER'
      when 'ADMIN' then 'ADMIN'
      when 'SUPER_ADMIN' then 'ADMIN'
      when 'PRIEST' then 'ADMIN'
      else 'USER'
    end::public.app_role_new
  );

alter table public.users alter column role set default 'USER'::public.app_role_new;

-- 2. Alter public.roles_permissions role column
alter table public.roles_permissions alter column role type public.app_role_new
  using (
    case role::text
      when 'PARISHIONER' then 'USER'
      when 'ADMIN' then 'ADMIN'
      when 'SUPER_ADMIN' then 'ADMIN'
      when 'PRIEST' then 'ADMIN'
      else 'USER'
    end::public.app_role_new
  );

-- 3. Alter public.announcements target_role column
alter table public.announcements alter column target_role type public.app_role_new
  using (
    case target_role::text
      when 'PARISHIONER' then 'USER'
      when 'ADMIN' then 'ADMIN'
      when 'SUPER_ADMIN' then 'ADMIN'
      when 'PRIEST' then 'ADMIN'
      else null
    end::public.app_role_new
  );

-- 4. Swap types
drop type public.app_role cascade;
alter type public.app_role_new rename to app_role;

-- 5. Re-create dropped policy on public.users
create policy p0_admin_update_users on public.users
  for update to authenticated
  using (public.is_admin())
  with check (
    public.is_admin()
    and role = (select u.role from public.users u where u.id = users.id)
  );

-- 6. Re-create helper functions to ensure consistency
create or replace function public.rbac_allows(p_role public.app_role, p_resource text, p_action text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.roles_permissions rp
    where rp.role = p_role and rp.resource = p_resource and rp.action = p_action
  )
$$;

create or replace function public.current_user_role()
returns text
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    (select u.role::text from public.users u
     where u.id = auth.uid() and u.deleted_at is null),
    'anon'
  )
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select public.current_user_role() = 'ADMIN'
$$;

create or replace function public.is_admin_or_priest()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select public.is_admin()
$$;

create or replace function public.is_super_admin()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select public.is_admin()
$$;

