-- ==============================================================================
-- 0046_payment_refunded_rpc.sql: Atomic Payment Refund Transition RPC
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.mark_payment_refunded(
  p_payment_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_payment_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_PAYMENT_ID' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.payments
  SET status = 'REFUNDED',
      updated_at = clock_timestamp()
  WHERE id = p_payment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PAYMENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
END;
$$;

-- Function Privilege Hardening (Locked Invariant)
REVOKE ALL ON FUNCTION public.mark_payment_refunded(BIGINT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_payment_refunded(BIGINT) TO service_role;
