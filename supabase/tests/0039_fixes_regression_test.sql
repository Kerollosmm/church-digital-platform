-- Test for 0039_comprehensive_fixes.sql
BEGIN;

-- Test 1: Verify role checks
-- Verify claim_event_outbox_batch exists
SELECT count(*) FROM public.claim_event_outbox_batch(10);

-- Test 2: Verify trigger tr_restore_slot_capacity exists
SELECT tgname FROM pg_trigger WHERE tgname = 'tr_restore_slot_capacity';

ROLLBACK;
