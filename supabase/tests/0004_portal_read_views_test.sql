-- supabase/tests/0004_portal_read_views_test.sql
do $$
declare v_count int;
begin
  set local role anon;
  select count(*) into v_count from public.v_services;
  if v_count < 1 then raise exception 'FAIL: v_services must expose seeded rows to anon'; end if;
  select count(*) into v_count from public.v_priests;
  if v_count < 1 then raise exception 'FAIL: v_priests must expose seeded rows to anon'; end if;
  select count(*) into v_count from public.v_faq;
  if v_count < 1 then raise exception 'FAIL: v_faq must expose seeded rows to anon'; end if;
  select count(*) into v_count from public.v_schedule_today;
  if v_count < 1 then raise exception 'FAIL: v_schedule_today must expose today''s slots to anon'; end if;
  if exists (
    select column_name from information_schema.columns
    where table_schema='public' and table_name='v_services'
      and column_name not in ('id','title_ar','description','location','next_slot_starts_at','price_from','tenant_id')
  ) then raise exception 'FAIL: v_services leaks columns'; end if;
end $$;
do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', (select id from public.users where role='ADMIN' limit 1), 'role','authenticated')::text, true);
  update public.services set title_ar = title_ar where id = (select id from public.services limit 1);
end $$;
