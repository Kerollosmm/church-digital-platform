BEGIN;

-- 0025: rbac helpers
do $$
declare v_u uuid; v_a uuid; v_n int;
begin
  insert into auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'r1@test.local', '+201011111111', '{}', '{}', now(), now()),
         ('00000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'r3@test.local', '+201011111113', '{}', '{}', now(), now())
  on conflict (id) do nothing;
  update public.users set role = 'USER', tenant_id = 1, deleted_at = null where id = '00000000-0000-0000-0000-000000000011';
  update public.users set role = 'ADMIN', tenant_id = 1, deleted_at = null where id = '00000000-0000-0000-0000-000000000013';
  insert into public.audit_log (action, entity_type, entity_id, meta) values ('TEST', 'TEST', 1, '{}');

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000011', 'role', 'authenticated')::text, true);
  if public.is_admin() or public.is_admin_or_priest() or public.is_super_admin()
  then raise exception 'FAIL: user must be denied by all helpers'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000013', 'role', 'authenticated')::text, true);
  if not public.is_admin() then raise exception 'FAIL: admin is admin'; end if;
  if not public.is_admin_or_priest() then raise exception 'FAIL: admin is admin_or_priest'; end if;

  -- policy smoke: user cannot select audit_log; admin can
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000011', 'role', 'authenticated')::text, true);
  select count(*) into v_n from public.audit_log;
  if v_n <> 0 then raise exception 'FAIL: user must not read audit_log'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000013', 'role', 'authenticated')::text, true);
  select count(*) into v_n from public.audit_log;
  if v_n = 0 then raise exception 'FAIL: admin must read audit_log'; end if;

  raise notice 'OK';
end $$;

ROLLBACK;
