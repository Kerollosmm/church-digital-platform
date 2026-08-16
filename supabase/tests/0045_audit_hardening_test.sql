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

-- 2. video_purchases unique constraint
SELECT tests.expect(
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

-- 6. Negative Authorization Tests: foreign tenant video_purchases is hidden under RLS
DO $$
DECLARE
  v_count INT;
BEGIN
  SET LOCAL ROLE authenticated;
  -- Set tenant context to 999 with regular non-admin user
  PERFORM set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000031", "app_metadata": {"tenant_id": 999}}', true);
  SELECT count(*) INTO v_count FROM public.video_purchases WHERE tenant_id = 1;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'RLS failed: foreign tenant video_purchases visible (% rows)', v_count;
  END IF;
END $$;

ROLLBACK;
