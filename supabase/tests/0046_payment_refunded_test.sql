BEGIN;
SELECT plan(4);

-- Fixture
INSERT INTO public.payments (id, amount, status, gateway_ref, tenant_id)
OVERRIDING SYSTEM VALUE
VALUES (99991, 50.00, 'PAID', 'txn_refund_test', 1);


-- 1. Service role can execute mark_payment_refunded
SET LOCAL ROLE service_role;
SELECT lives_ok(
  $$ SELECT public.mark_payment_refunded(99991::bigint) $$,
  'service_role can execute mark_payment_refunded'
);

RESET ROLE;
SELECT is(
  (SELECT status::text FROM public.payments WHERE id = 99991),
  'REFUNDED',
  'Payment status is transitioned to REFUNDED'
);

-- 2. Negative Authorization Tests: anon execution denied
DO $$
BEGIN
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.mark_payment_refunded(99991::bigint);
    RAISE EXCEPTION 'Negative authorization check failed: anon executed mark_payment_refunded';
  EXCEPTION
    WHEN insufficient_privilege THEN
      -- Expected SQLSTATE 42501
      NULL;
    WHEN OTHERS THEN
      IF SQLSTATE = '42501' THEN
        NULL;
      ELSE
        RAISE;
      END IF;
  END;
END $$;
SELECT pass('Anon execution of mark_payment_refunded is denied');

-- 3. Negative Authorization Tests: authenticated execution denied
DO $$
BEGIN
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.mark_payment_refunded(99991::bigint);
    RAISE EXCEPTION 'Negative authorization check failed: authenticated executed mark_payment_refunded';
  EXCEPTION
    WHEN insufficient_privilege THEN
      -- Expected SQLSTATE 42501
      NULL;
    WHEN OTHERS THEN
      IF SQLSTATE = '42501' THEN
        NULL;
      ELSE
        RAISE;
      END IF;
  END;
END $$;
SELECT pass('Authenticated execution of mark_payment_refunded is denied');

SELECT * FROM finish();
ROLLBACK;
