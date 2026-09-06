\set ON_ERROR_STOP on

BEGIN;

create schema if not exists tests;
create or replace function tests.expect(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if not p_cond then raise exception 'FAIL: %', p_msg; end if;
end $$;

do $$
begin
  perform tests.expect(
    not exists (
      select 1 from pg_publication_rel pr
      join pg_publication p on p.oid = pr.prpubid
      join pg_class c on c.oid = pr.prrelid
      join pg_namespace n on n.oid = c.relnamespace
      where p.pubname = 'supabase_realtime' and n.nspname = 'public' and c.relname = 'bookings'
    ),
    'public.bookings must not be in supabase_realtime publication'
  );

  perform tests.expect(
    exists (
      select 1 from pg_publication_rel pr
      join pg_publication p on p.oid = pr.prpubid
      join pg_class c on c.oid = pr.prrelid
      join pg_namespace n on n.oid = c.relnamespace
      where p.pubname = 'supabase_realtime' and n.nspname = 'public' and c.relname = 'service_slots'
    ),
    'public.service_slots must be in supabase_realtime publication'
  );
end $$;

ROLLBACK;
