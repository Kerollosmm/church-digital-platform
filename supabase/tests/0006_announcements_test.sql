do $$
begin
  set local role anon;
  if exists (select 1 from public.announcements where published_at > now())
  then raise exception 'FAIL: anon must not see unpublished announcements'; end if;
  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', (select id from public.users where role='ADMIN' limit 1), 'role','authenticated')::text, true);
  insert into public.announcements (title_ar, body_ar, published_at, tenant_id)
  values ('اعلان تجريبي', 'نص', now(), public.tenant_id());
  set local role anon;
  if not exists (select 1 from public.announcements where title_ar='اعلان تجريبي')
  then raise exception 'FAIL: published announcement must be visible to anon'; end if;
end $$;
