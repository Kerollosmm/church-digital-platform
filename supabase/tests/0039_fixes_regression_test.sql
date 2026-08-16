BEGIN;

-- Test for 0039_comprehensive_fixes.sql & 0041_restrict_event_outbox_claim.sql
DO $$
DECLARE
  v_denied boolean;
BEGIN
  -- Test 1: anon role is denied EXECUTE on claim_event_outbox_batch
  SET LOCAL ROLE anon;
  v_denied := false;
  BEGIN
    PERFORM public.claim_event_outbox_batch(10);
  EXCEPTION WHEN OTHERS THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'FAIL: anon must NOT be allowed to execute claim_event_outbox_batch';
  END IF;

  -- Test 2: authenticated role is denied EXECUTE on claim_event_outbox_batch
  SET LOCAL ROLE authenticated;
  v_denied := false;
  BEGIN
    PERFORM public.claim_event_outbox_batch(10);
  EXCEPTION WHEN OTHERS THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'FAIL: authenticated must NOT be allowed to execute claim_event_outbox_batch';
  END IF;

  -- Test 3: service_role can execute claim_event_outbox_batch
  SET LOCAL ROLE service_role;
  PERFORM count(*) FROM public.claim_event_outbox_batch(10);

  -- Test 4: Verify trigger tr_restore_slot_capacity exists
  RESET ROLE;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'tr_restore_slot_capacity') THEN
    RAISE EXCEPTION 'FAIL: tr_restore_slot_capacity trigger must exist';
  END IF;

  RAISE NOTICE '0039_fixes_regression_test: OK';
END $$;

ROLLBACK;
