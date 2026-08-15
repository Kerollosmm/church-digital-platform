-- 0003: RBAC matrix (9 resources x 4 actions). Phase 0 owns 0001-0003.

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

insert into public.roles_permissions (role, resource, action)
select 'USER'::public.app_role, u.resource, u.action from (values
  ('users','READ'),('services','READ'),('service_slots','READ'),('bookings','READ'),
  ('payments','READ'),('videos','READ'),('video_purchases','READ'),('announcements','READ'),
  ('bookings','CREATE'),('complaints','CREATE')
) as u(resource, action) on conflict do nothing;

insert into public.roles_permissions (role, resource, action)
select 'ADMIN'::public.app_role, u.resource, u.action
from (select r.resource, a.action
      from (values ('users'),('services'),('service_slots'),('bookings'),('payments'),
                   ('videos'),('video_purchases'),('complaints'),('announcements')) as r(resource)
      cross join (values ('READ'),('CREATE'),('UPDATE'),('DELETE')) as a(action)
     ) u on conflict do nothing;

