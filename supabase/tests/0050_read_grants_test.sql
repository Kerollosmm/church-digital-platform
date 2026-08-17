\set ON_ERROR_STOP on

create schema if not exists tests;
create or replace function tests.expect(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if not p_cond then raise exception 'FAIL: %', p_msg; end if;
end $$;
grant usage on schema tests to anon, authenticated, service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;

BEGIN;

-- ==============================================================================
-- 0050_read_grants_test.sql
-- Assert table-level read grants for anon/authenticated and deny on restricted tables
-- ==============================================================================

-- 1. Test anon role permissions
DO $$
DECLARE
  v_count bigint;
  v_denied boolean := false;
BEGIN
  SET LOCAL ROLE anon;
  PERFORM set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000000","role":"anon"}', true);

  -- Anon can SELECT count from public read / RLS guarded tables
  SELECT count(*) INTO v_count FROM public.bookings;
  PERFORM tests.expect(v_count >= 0, 'anon must be able to SELECT from public.bookings');

  SELECT count(*) INTO v_count FROM public.services;
  PERFORM tests.expect(v_count >= 0, 'anon must be able to SELECT from public.services');

  SELECT count(*) INTO v_count FROM public.announcements;
  PERFORM tests.expect(v_count >= 0, 'anon must be able to SELECT from public.announcements');

  -- Anon CANNOT select from restricted tables (event_outbox)
  BEGIN
    SELECT count(*) INTO v_count FROM public.event_outbox;
    v_denied := false;
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_denied := true;
  END;
  PERFORM tests.expect(v_denied, 'anon must receive permission denied (42501) on public.event_outbox');

  RESET ROLE;
END $$;

-- 2. Test authenticated role permissions
DO $$
DECLARE
  v_count bigint;
BEGIN
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000050","role":"authenticated"}', true);

  SELECT count(*) INTO v_count FROM public.bookings;
  PERFORM tests.expect(v_count >= 0, 'authenticated must be able to SELECT from public.bookings');

  RESET ROLE;
END $$;

ROLLBACK;
