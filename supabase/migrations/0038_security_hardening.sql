-- 0038: security hardening & tenant precedence migration for existing deployments
create or replace function public.tenant_id()
returns bigint
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    (select u.tenant_id::text from public.users u where u.id = auth.uid() and u.deleted_at is null),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'tenant_id',
    '1'
  )::bigint
$$;

grant execute on function public.tenant_id() to anon, authenticated, service_role;
