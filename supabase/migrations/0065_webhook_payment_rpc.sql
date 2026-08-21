-- ==============================================================================
-- 0065_webhook_payment_rpc.sql
-- 010-fix-review-findings US1 (follow-up to 0064): complete the RPC surface so
-- paymob-webhook and paymob-checkout never touch the payments table directly.
--   1) create_pending_payment now stamps merchant_order_id (checkout drops its
--      direct UPDATE)
--   2) NEW record_webhook_payment: service-role-only upsert for webhook events
--      (existing row update or orphan insert with booking_id NULL)
--   3) mark_payment_failed accepts optional detail jsonb (reconcile reason)
-- Forward-only: 0064 is NOT modified.
-- ==============================================================================

-- ---------------------------------------------------------------------------
-- 1. create_pending_payment: stamp merchant_order_id at creation
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_pending_payment(
  p_booking_id bigint,
  p_amount numeric,
  p_gateway_ref text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_is_service boolean := coalesce(auth.role(), '') = 'service_role' OR current_user = 'service_role';
  v_booking public.bookings;
  v_pay_id bigint;
  v_ref text;
BEGIN
  IF v_user_id IS NULL AND NOT v_is_service THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_booking FROM public.bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_booking IS NULL THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF NOT v_is_service AND v_booking.user_id <> v_user_id THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF v_booking.status <> 'PENDING_PAYMENT' THEN
    RAISE EXCEPTION 'INVALID_STATUS: booking is not pending payment' USING ERRCODE = 'P0001';
  END IF;

  v_ref := COALESCE(p_gateway_ref, 'pay_' || extract(epoch from clock_timestamp())::bigint || '_' || p_booking_id);

  INSERT INTO public.payments (
    booking_id, amount, status, gateway_ref, tenant_id
  ) VALUES (
    p_booking_id, COALESCE(p_amount::int, 0), 'CREATED', v_ref, v_booking.tenant_id
  ) RETURNING id INTO v_pay_id;

  -- Checkout identifies the Paymob order by the payment id itself.
  UPDATE public.payments SET merchant_order_id = v_pay_id::text WHERE id = v_pay_id;

  RETURN v_pay_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_pending_payment(bigint, numeric, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_pending_payment(bigint, numeric, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. record_webhook_payment: idempotent webhook outcome recorder
--    Returns jsonb {"id": <payment id>, "already_paid": <bool>}
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_webhook_payment(
  p_merchant_order_id text,
  p_gateway_ref text,
  p_amount int,
  p_paid boolean,
  p_raw jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_existing public.payments;
  v_pay_id bigint;
BEGIN
  IF NOT (coalesce(auth.role(), '') = 'service_role' OR current_user = 'service_role') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  IF p_merchant_order_id IS NULL OR p_merchant_order_id = '' THEN
    RAISE EXCEPTION 'INVALID_MERCHANT_ORDER_ID' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_existing FROM public.payments
   WHERE merchant_order_id = p_merchant_order_id
   ORDER BY id LIMIT 1 FOR UPDATE;

  IF v_existing.id IS NOT NULL THEN
    -- Idempotency: a PAID row is terminal; acknowledge without rewriting it.
    IF v_existing.status = 'PAID' THEN
      RETURN jsonb_build_object('id', v_existing.id, 'already_paid', true);
    END IF;

    UPDATE public.payments
       SET gateway_ref = COALESCE(p_gateway_ref, gateway_ref),
           raw_webhook = p_raw,
           status = CASE WHEN p_paid THEN status ELSE 'FAILED' END,
           updated_at = clock_timestamp()
     WHERE id = v_existing.id
     RETURNING id INTO v_pay_id;

    RETURN jsonb_build_object('id', v_pay_id, 'already_paid', false);
  END IF;

  -- Unknown order (e.g. legacy/manual checkout): keep an audit trail as an
  -- orphan payment row (booking_id NULL) exactly as the webhook did before.
  INSERT INTO public.payments (
    booking_id, gateway_ref, amount, status, raw_webhook, merchant_order_id, tenant_id
  ) VALUES (
    NULL, p_gateway_ref, COALESCE(p_amount, 0),
    CASE WHEN p_paid THEN 'CREATED'::public.payment_status ELSE 'FAILED'::public.payment_status END,
    p_raw, p_merchant_order_id, COALESCE(public.tenant_id(), 1)
  ) RETURNING id INTO v_pay_id;

  RETURN jsonb_build_object('id', v_pay_id, 'already_paid', false);
END;
$$;

REVOKE ALL ON FUNCTION public.record_webhook_payment(text, text, int, boolean, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_webhook_payment(text, text, int, boolean, jsonb)
  TO service_role;

-- ---------------------------------------------------------------------------
-- 3. mark_payment_failed: optional structured failure detail
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_payment_failed(
  p_payment_id BIGINT,
  p_detail jsonb DEFAULT NULL
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

  IF NOT (coalesce(auth.role(), '') = 'service_role' OR current_user = 'service_role') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  UPDATE public.payments
     SET status = 'FAILED',
         raw_webhook = COALESCE(p_detail, raw_webhook),
         updated_at = clock_timestamp()
   WHERE id = p_payment_id
     AND status IN ('CREATED', 'PENDING');

  IF NOT FOUND THEN
    SELECT status::text INTO v_status FROM public.payments WHERE id = p_payment_id;
    IF v_status IS NULL THEN
      RAISE EXCEPTION 'PAYMENT_NOT_FOUND' USING ERRCODE = 'P0002';
    ELSIF v_status = 'FAILED' THEN
      RETURN; -- idempotent no-op
    ELSE
      RAISE EXCEPTION 'INVALID_STATUS: %', v_status USING ERRCODE = 'P0003';
    END IF;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_payment_failed(BIGINT, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_payment_failed(BIGINT, jsonb) TO service_role;

-- Superseded single-arg overload removed to keep one canonical signature
DROP FUNCTION IF EXISTS public.mark_payment_failed(BIGINT);
