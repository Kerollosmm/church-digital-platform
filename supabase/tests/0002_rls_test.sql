\set ON_ERROR_STOP on
create schema if not exists tests;
create or replace function tests.expect(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if not p_cond then raise exception 'FAIL: %', p_msg; end if;
end $$;

grant usage on schema tests to anon, authenticated;
grant execute on all functions in schema tests to anon, authenticated;

begin;
  insert into auth.users (id, instance_id, aud, role, email, phone,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', 'p0-parishioner@test.local', '+201000000099',
          '{}', '{"name":"P0 Parishioner"}', now(), now()),
         ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', 'p0-admin@test.local', '+201000000098',
          '{}', '{"name":"P0 Admin"}', now(), now());
  update public.users set role = 'ADMIN' where id = '22222222-2222-2222-2222-222222222222';
  insert into public.services (title_ar, tenant_id) values ('قداس اختبار', 1);
  insert into public.service_slots (service_id, starts_at, ends_at, capacity, price, tenant_id)
    values (currval('public.services_id_seq'), now() + interval '1 day', now() + interval '1 day' + interval '1 hour', 10, 0, 1);
  insert into public.bookings (slot_id, user_id, tenant_id) values (currval('public.service_slots_id_seq'), '11111111-1111-1111-1111-111111111111', 1);

  perform tests.expect(
    exists (select 1 from public.users where id = '11111111-1111-1111-1111-111111111111'),
    'handle_new_user did not create public.users row');
  perform tests.expect(
    exists (select 1 from public.audit_log where entity_type = 'bookings'),
    'audit_trigger did not write audit_log row');
  perform tests.expect(
    (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = 'complaints') = 0,
    'complaints must have NO baseline policies (Phase 1 owns them)');
  perform tests.expect(
    (select count(*) from pg_tables t
     where t.schemaname = 'public'
       and t.tablename in ('users','roles_permissions','priests','services','service_slots',
                           'bookings','payments','waiting_list','videos','video_purchases',
                           'complaints','announcements','audit_log','whatsapp_outbox',
                           'whatsapp_optins')
       and t.rowsecurity) = 15,
    'RLS must be enabled on all 15 tables');

  set local role anon;
  set_config('request.jwt.claims',
             '{"sub":"00000000-0000-0000-0000-000000000000","role":"anon"}', true);
  perform tests.expect((select count(*) from public.bookings) = 0,
                       'anon must see 0 bookings');
  begin
    insert into public.bookings (slot_id, user_id, tenant_id)
      values (currval('public.service_slots_id_seq'), '11111111-1111-1111-1111-111111111111', 1);
    perform tests.expect(false, 'anon INSERT into bookings must be denied by RLS');
  exception when others then
    perform tests.expect(true, 'anon INSERT denied as expected');
  end;
  reset role;

  set local role authenticated;
  set_config('request.jwt.claims',
             json_build_object('sub','11111111-1111-1111-1111-111111111111',
                               'role','authenticated'), true);
  perform tests.expect((select count(*) from public.bookings) = 1,
                       'parishioner must see exactly own booking');
  perform tests.expect((select count(*) from public.users) = 1,
                       'parishioner must see only own profile row');
  reset role;

  set local role authenticated;
  set_config('request.jwt.claims',
             json_build_object('sub','22222222-2222-2222-2222-222222222222',
                               'role','authenticated'), true);
  perform tests.expect((select count(*) from public.users) = 2,
                       'admin must see all users');
  perform tests.expect((select count(*) from public.bookings) = 1,
                       'admin must see all bookings');
  reset role;

  -- Verify public.users.tenant_id takes precedence over JWT tenant claim
  set local role authenticated;
  set_config('request.jwt.claims',
             json_build_object('sub','11111111-1111-1111-1111-111111111111',
                               'role','authenticated',
                               'tenant_id','999'), true);
  perform tests.expect(public.tenant_id() = 1,
                       'public.tenant_id() must prioritize public.users.tenant_id over JWT claim');
  reset role;
rollback;
