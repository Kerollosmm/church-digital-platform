begin;
select plan(4);

select has_column('public', 'audit_log', 'entity_uuid',
  'audit_log has entity_uuid column');

select is(
  (select proconfig::text from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'apply_payment'),
  (select proconfig::text from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'apply_payment'),
  'apply_payment exists (sanity)'
);

select is(
  position('pg_temp' in coalesce((select proconfig::text from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'apply_payment'), '')) > 0,
  true,
  'apply_payment search_path includes pg_temp'
);

-- fixtures
insert into auth.users (id, email, phone) values
  ('ffffffff-0000-0000-0000-000000008201'::uuid, 'user8201@test.com', '+201000008201')
on conflict (id) do update set email = excluded.email, phone = excluded.phone;

insert into public.users (id, phone, name, role, tenant_id) values
  ('ffffffff-0000-0000-0000-000000008201'::uuid, '+201000008201', 'Member 82', 'USER', 1)
on conflict (id) do update set role = excluded.role;

insert into public.event_types (id, name_ar, base_price_piastres, default_duration_minutes, tenant_id)
values ('aaaaaaaa-8282-8282-8282-828282828282'::uuid, 'معمودية 82', 25000, 60, 1)
on conflict (id) do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000008201"}';

select public.submit_event_booking(
  'aaaaaaaa-8282-8282-8282-828282828282'::uuid,
  now() + interval '5 days',
  '[]'::jsonb
);

reset role;

select is(
  (select count(*) from public.audit_log
    where action = 'submit_event_booking'
      and entity_type = 'event_bookings'
      and entity_uuid is not null),
  1::bigint,
  'submit_event_booking audit row records entity_uuid'
);

select * from finish();
rollback;
