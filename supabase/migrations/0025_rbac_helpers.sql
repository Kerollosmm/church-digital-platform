-- 0025: centralized role checks (replaces repeated current_user_role() predicates)
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.current_user_role() = 'ADMIN'
$$;

create or replace function public.is_admin_or_priest()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_admin()
$$;

create or replace function public.is_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_admin()
$$;

grant execute on function public.is_admin() to anon, authenticated, service_role;
grant execute on function public.is_admin_or_priest() to anon, authenticated, service_role;
grant execute on function public.is_super_admin() to anon, authenticated, service_role;
