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
DECLARE
  v_status text;
BEGIN
  IF p_payment_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_PAYMENT_ID' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.payments
  SET status = 'REFUNDED',
      updated_at = clock_timestamp()
  WHERE id = p_payment_id AND status IN ('PAID', 'REFUND_PENDING');

  IF NOT FOUND THEN
    SELECT status::text INTO v_status FROM public.payments WHERE id = p_payment_id;
    IF v_status IS NULL THEN
      RAISE EXCEPTION 'PAYMENT_NOT_FOUND' USING ERRCODE = 'P0002';
    ELSE
      RAISE EXCEPTION 'INVALID_STATUS: %', v_status USING ERRCODE = 'P0003';
    END IF;
  END IF;
END;
$$;

-- Function Privilege Hardening (Locked Invariant)
REVOKE ALL ON FUNCTION public.mark_payment_refunded(BIGINT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_payment_refunded(BIGINT) TO service_role;
