\set ON_ERROR_STOP on

BEGIN;

do $$
begin
  if current_database() <> 'postgres' then
    raise exception 'FAIL: expected database postgres, got %', current_database();
  end if;
  if not exists (select 1 from pg_namespace where nspname = 'auth') then
    raise exception 'FAIL: auth schema missing (Supabase Auth not running)';
  end if;
  if not exists (select 1 from pg_tables where schemaname = 'auth' and tablename = 'users') then
    raise exception 'FAIL: auth.users table missing';
  end if;
end $$;

ROLLBACK;
