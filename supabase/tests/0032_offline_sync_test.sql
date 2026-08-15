\set ON_ERROR_STOP on
create schema if not exists tests;
create or replace function tests.expect(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if not p_cond then raise exception 'FAIL: %', p_msg; end if;
end $$;

do $$
begin
  -- 1. Table existence
  perform tests.expect(
    exists (
      select 1 from information_schema.tables 
      where table_schema = 'public' and table_name = 'offline_sync_log'
    ),
    'public.offline_sync_log table must exist'
  );

  -- 2. RLS enabled
  perform tests.expect(
    exists (
      select 1 from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = 'offline_sync_log' and c.relrowsecurity = true
    ),
    'public.offline_sync_log must have RLS enabled'
  );

  -- 3. Function existence
  perform tests.expect(
    exists (
      select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'sync_offline_mutations'
    ),
    'public.sync_offline_mutations function must exist'
  );
end $$;
