-- 0040: Fix complaints read access safely
-- Recreates v_my_complaints and v_complaints with security_invoker = false
-- to safely allow metadata access while keeping body_encrypted protected.

drop view if exists public.v_my_complaints;
create view public.v_my_complaints with (security_invoker = false) as
select id, category, status, assigned_to, created_at
from public.complaints
where user_id = auth.uid() and tenant_id = public.tenant_id();

drop view if exists public.v_complaints;
create view public.v_complaints with (security_invoker = false) as
select id, user_id, category, status, assigned_to, created_at
from public.complaints
where public.is_admin()
  and tenant_id = public.tenant_id();

revoke all on public.v_my_complaints from anon;
grant select on public.v_my_complaints to authenticated;

revoke all on public.v_complaints from anon;
grant select on public.v_complaints to authenticated;
