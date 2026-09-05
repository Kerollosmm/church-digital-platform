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

-- Fixtures
INSERT INTO public.payments (id, amount, status, gateway_ref, tenant_id)
OVERRIDING SYSTEM VALUE
VALUES 
  (99991, 5000, 'PAID', 'txn_paid_test', 1),
  (99992, 7500, 'REFUND_PENDING', 'txn_refund_pending_test', 1),
  (99993, 10000, 'PENDING', 'txn_pending_test', 1);

-- 1. PAID -> REFUNDED transition succeeds
SET LOCAL ROLE service_role;
SELECT public.mark_payment_refunded(99991::bigint);
RESET ROLE;
SELECT tests.expect(
  (SELECT status::text FROM public.payments WHERE id = 99991) = 'REFUNDED',
  'Payment 99991 status is transitioned to REFUNDED'
);

-- 2. REFUND_PENDING -> REFUNDED transition succeeds
SET LOCAL ROLE service_role;
SELECT public.mark_payment_refunded(99992::bigint);
RESET ROLE;
SELECT tests.expect(
  (SELECT status::text FROM public.payments WHERE id = 99992) = 'REFUNDED',
  'Payment 99992 status is transitioned to REFUNDED'
);

-- 3. PENDING -> REFUNDED raises INVALID_STATUS
DO $$
BEGIN
  SET LOCAL ROLE service_role;
  BEGIN
    PERFORM public.mark_payment_refunded(99993::bigint);
    RAISE EXCEPTION 'Expected INVALID_STATUS exception for PENDING payment';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%INVALID_STATUS%' THEN
        NULL;
      ELSE
        RAISE;
      END IF;
  END;
END $$;

-- 4. Nonexistent payment ID raises PAYMENT_NOT_FOUND
DO $$
BEGIN
  SET LOCAL ROLE service_role;
  BEGIN
    PERFORM public.mark_payment_refunded(999999::bigint);
    RAISE EXCEPTION 'Expected PAYMENT_NOT_FOUND exception for nonexistent payment';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%PAYMENT_NOT_FOUND%' THEN
        NULL;
      ELSE
        RAISE;
      END IF;
  END;
END $$;

-- 5. Negative Authorization Tests: anon execution denied
DO $$
BEGIN
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.mark_payment_refunded(99991::bigint);
    RAISE EXCEPTION 'Negative authorization check failed: anon executed mark_payment_refunded';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
    WHEN OTHERS THEN
      IF SQLSTATE = '42501' THEN NULL; ELSE RAISE; END IF;
  END;
END $$;

-- 6. Negative Authorization Tests: authenticated execution denied
DO $$
BEGIN
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.mark_payment_refunded(99991::bigint);
    RAISE EXCEPTION 'Negative authorization check failed: authenticated executed mark_payment_refunded';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
    WHEN OTHERS THEN
      IF SQLSTATE = '42501' THEN NULL; ELSE RAISE; END IF;
  END;
END $$;

ROLLBACK;
