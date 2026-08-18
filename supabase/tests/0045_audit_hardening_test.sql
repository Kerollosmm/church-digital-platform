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

-- 1. claim_event_outbox_batch signature & execution
DO $$
BEGIN
  PERFORM public.claim_event_outbox_batch(10);
END $$;

-- 2. Negative Authorization Tests: anon execution of claim_event_outbox_batch is denied
DO $$
BEGIN
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.claim_event_outbox_batch(10);
    RAISE EXCEPTION 'Negative authorization check failed: anon executed claim_event_outbox_batch';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
    WHEN OTHERS THEN
      IF SQLSTATE = '42501' THEN NULL; ELSE RAISE; END IF;
  END;
END $$;

-- 3. Negative Authorization Tests: authenticated execution of claim_event_outbox_batch is denied
DO $$
BEGIN
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.claim_event_outbox_batch(10);
    RAISE EXCEPTION 'Negative authorization check failed: authenticated executed claim_event_outbox_batch';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
    WHEN OTHERS THEN
      IF SQLSTATE = '42501' THEN NULL; ELSE RAISE; END IF;
  END;
END $$;

ROLLBACK;
