begin;
select plan(5);

select has_column('public', 'offline_sync_log', 'tenant_id',
  'offline_sync_log has tenant_id column');

select col_not_null('public', 'offline_sync_log', 'tenant_id',
  'offline_sync_log.tenant_id is NOT NULL');

select is(
  (select count(*) from pg_policies
    where schemaname = 'public'
      and tablename = 'offline_sync_log'
      and (qual like '%tenant_id%' or with_check like '%tenant_id%')),
  1::bigint,
  'offline_sync_log RLS policy checks tenant_id'
);

select is(
  (select has_table_privilege('authenticated', 'public.offline_sync_log', 'INSERT, UPDATE, DELETE')),
  false,
  'authenticated has no direct write DML on offline_sync_log'
);

select is(
  (select has_table_privilege('authenticated', 'public.offline_sync_log', 'SELECT')),
  true,
  'authenticated retains SELECT via read grant'
);

select * from finish();
rollback;
