-- 0025: rbac helpers
do $$
declare v_u uuid; v_a uuid; v_n int;
begin
  insert into public.users (id, phone, name, role, tenant_id) values
    ('00000000-0000-0000-0000-000000000011', '+201011111111', 'p', 'USER', 1),
    ('00000000-0000-0000-0000-000000000013', '+201011111113', 'a', 'ADMIN', 1);

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000011', 'role', 'authenticated')::text, true);
  if public.is_admin() or public.is_admin_or_priest() or public.is_super_admin()
  then raise exception 'FAIL: user must be denied by all helpers'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000013', 'role', 'authenticated')::text, true);
  if not public.is_admin() then raise exception 'FAIL: admin is admin'; end if;
  if not public.is_admin_or_priest() then raise exception 'FAIL: admin is admin_or_priest'; end if;

  -- policy smoke: user cannot select service_slots (0011 + p0_admin_all); admin can
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000011', 'role', 'authenticated')::text, true);
  select count(*) into v_n from public.service_slots;
  if v_n <> 0 then raise exception 'FAIL: user must not read service_slots'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000013', 'role', 'authenticated')::text, true);
  select count(*) into v_n from public.service_slots;
  if v_n = 0 then raise exception 'FAIL: admin must read service_slots'; end if;

  raise notice 'OK';
end $$;
