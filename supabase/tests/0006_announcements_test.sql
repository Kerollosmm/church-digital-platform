do $$
begin
  insert into auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', 'admin-ann@test.local', '+201000000097', '{}', '{"name":"Admin"}', now(), now())
  on conflict (id) do nothing;
  update public.users set role = 'ADMIN', tenant_id = 1 where id = '22222222-2222-2222-2222-222222222222';

  set local role anon;
  if exists (select 1 from public.announcements where published_at > now())
  then raise exception 'FAIL: anon must not see unpublished announcements'; end if;
  reset role;
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
  insert into public.announcements (title_ar, body_ar, published_at, tenant_id)
  values ('اعلان تجريبي', 'نص', now(), 1);
  set local role anon;
  if not exists (select 1 from public.announcements where title_ar='اعلان تجريبي')
  then raise exception 'FAIL: published announcement must be visible to anon'; end if;
end $$;
