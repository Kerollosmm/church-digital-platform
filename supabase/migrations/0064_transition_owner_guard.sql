-- ==============================================================================
-- 0064_transition_owner_guard.sql
-- 010-fix-review-findings US1:
--   1) close the apply_payment ownership bypass in transition_booking_status
--      (any authenticated caller could pass p_action='apply_payment' to advance
--       another user's booking); stale 'PRIEST' tier removed
--   2) additive payment lifecycle RPCs so integration code never writes the
--      payments table directly: create_pending_payment / mark_payment_failed
-- Forward-only: applied migration 0063 is NOT modified.
-- ==============================================================================

-- ---------------------------------------------------------------------------
-- 1. transition_booking_status: uniform ownership guard
-- ---------------------------------------------------------------------------
create or replace function public.transition_booking_status(
  p_booking_id bigint,
  p_new_status public.booking_status,
  p_action text,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
) returns public.bookings language plpgsql security definer set search_path = public as $$
declare
  v_book public.bookings;
  v_old_status public.booking_status;
  v_role text := public.current_user_role();
  v_is_service boolean := coalesce(auth.role(), '') = 'service_role' or current_user = 'service_role';
begin
  select * into v_book from public.bookings where id = p_booking_id for update;
  if v_book is null then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_book.status = p_new_status then return v_book; end if;

  -- SECURITY DEFINER must never widen access: re-assert gates here.
  -- Allowed callers: admin tier, the booking owner, or the service role.
  -- No action-string escape hatches (the 0063 'apply_payment' bypass is closed).
  if not (
    v_is_service
    or public.is_admin()
    or v_book.user_id = auth.uid()
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- Regular users can only cancel their own bookings, or reach AWAITING_CALL via apply_payment
  if not (v_is_service or public.is_admin()) then
    if p_new_status not in ('CANCELLED') and not (p_action = 'apply_payment' and p_new_status = 'AWAITING_CALL') then
      raise exception 'FORBIDDEN: users can only cancel bookings' using errcode = '42501';
    end if;
  end if;

  v_old_status := v_book.status;
  update public.bookings
     set status = p_new_status,
         locked_until = case when p_new_status = 'PENDING_PAYMENT' then locked_until else null end,
         updated_at = now()
   where id = p_booking_id
   returning * into v_book;

  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (auth.uid(), p_action, 'bookings', p_booking_id,
          jsonb_build_object('old_status', v_old_status, 'new_status', p_new_status,
                             'reason', p_reason, 'slot_id', v_book.slot_id) || p_metadata);
  return v_book;
end $$;

REVOKE ALL ON FUNCTION public.transition_booking_status(bigint, public.booking_status, text, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.transition_booking_status(bigint, public.booking_status, text, text, jsonb)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. create_pending_payment: insert-only CREATED payment (checkout start)
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
  v_is_service boolean := coalesce(auth.role(), '') = 'service_role' or current_user = 'service_role';
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

  RETURN v_pay_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_pending_payment(bigint, numeric, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_pending_payment(bigint, numeric, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. mark_payment_failed: service-role-only FAILED transition (never touches PAID)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_payment_failed(
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

  IF NOT (coalesce(auth.role(), '') = 'service_role' OR current_user = 'service_role') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  -- Idempotent: already-FAILED rows match no rows and fall through to the
  -- NOT FOUND probe below, which returns the row without raising on FAILED.
  UPDATE public.payments
     SET status = 'FAILED',
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

REVOKE ALL ON FUNCTION public.mark_payment_failed(BIGINT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_payment_failed(BIGINT) TO service_role;


