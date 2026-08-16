BEGIN;
SELECT plan(6);

-- 1. claim_event_outbox_batch signature & execution
SELECT lives_ok(
  $$ SELECT * FROM public.claim_event_outbox_batch(10) $$,
  'claim_event_outbox_batch should lease rows without schema error'
);

-- 2. video_purchases unique constraint
SELECT ok(
  EXISTS(SELECT 1 FROM pg_constraint WHERE conname = 'uq_video_purchases_user_video'),
  'video_purchases should have unique constraint uq_video_purchases_user_video'
);

-- 3. Negative Authorization Tests: anon execution of claim_event_outbox_batch is denied
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
SELECT pass('Anon execution of claim_event_outbox_batch is denied');

-- 4. Negative Authorization Tests: authenticated execution of claim_event_outbox_batch is denied
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
SELECT pass('Authenticated execution of claim_event_outbox_batch is denied');

-- 5. Negative Authorization Tests: anon execution of purchase_video is denied
DO $$
BEGIN
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.purchase_video(1::bigint);
    RAISE EXCEPTION 'Negative authorization check failed: anon executed purchase_video';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
    WHEN OTHERS THEN
      IF SQLSTATE IN ('42501', '28000') THEN NULL; ELSE RAISE; END IF;
  END;
END $$;
SELECT pass('Anon execution of purchase_video is denied');

-- 6. Negative Authorization Tests: foreign tenant video_purchases is hidden under RLS
DO $$
DECLARE
  v_count INT;
BEGIN
  SET LOCAL ROLE authenticated;
  -- Set tenant context to 999
  PERFORM set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "app_metadata": {"tenant_id": 999}}', true);
  SELECT count(*) INTO v_count FROM public.video_purchases WHERE tenant_id = 1;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'RLS failed: foreign tenant video_purchases visible (% rows)', v_count;
  END IF;
END $$;
SELECT pass('Foreign tenant video_purchases is hidden under RLS');

SELECT * FROM finish();
ROLLBACK;
