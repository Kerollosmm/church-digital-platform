-- ==============================================================================
-- 0048_role_gates_and_storage_guard.sql
-- Purpose: Consolidate role gate whitelist ('USER') & hardened storage RLS guard
-- ==============================================================================

-- 1. Update book_slot with 'USER' role in whitelist
CREATE OR REPLACE FUNCTION public.book_slot(
  p_slot_id bigint,
  p_opt_in boolean default false
) RETURNS public.bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_role text := public.current_user_role();
  v_slot public.service_slots;
  v_mine int;
  v_active int;
  v_book public.bookings;
  v_phone text;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '28000'; END IF;
  IF v_role NOT IN ('USER','ADMIN','PRIEST','PARISHIONER') THEN RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_slot FROM public.service_slots WHERE id = p_slot_id FOR UPDATE;
  IF v_slot IS NULL OR v_slot.status = 'CLOSED' OR v_slot.starts_at <= now()
  THEN RAISE EXCEPTION 'SLOT_UNAVAILABLE' USING ERRCODE = 'P0001'; END IF;
  SELECT count(*) INTO v_mine FROM public.bookings
  WHERE user_id = v_user AND status IN ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED');
  IF v_mine >= 3 THEN RAISE EXCEPTION 'TOO_MANY_ACTIVE_BOOKINGS' USING ERRCODE = 'P0001'; END IF;
  IF EXISTS (SELECT 1 FROM public.bookings
             WHERE slot_id = p_slot_id AND user_id = v_user
               AND status IN ('PENDING_PAYMENT','AWAITING_CALL','CONFIRMED'))
  THEN RAISE EXCEPTION 'ALREADY_BOOKED_SLOT' USING ERRCODE = 'P0001'; END IF;
  SELECT public.active_booking_count(p_slot_id) INTO v_active;
  IF v_active >= v_slot.capacity THEN RAISE EXCEPTION 'SLOT_FULL' USING ERRCODE = 'P0001'; END IF;
  IF p_opt_in THEN
    SELECT phone INTO v_phone FROM public.users WHERE id = v_user;
    IF v_phone IS NOT NULL THEN
      INSERT INTO public.whatsapp_optins (phone, source) VALUES (v_phone, 'BOOKING')
      ON CONFLICT (phone) DO UPDATE SET consented_at = now();
    END IF;
  END IF;
  INSERT INTO public.bookings (slot_id, user_id, status, paid_amount, locked_until, created_by, tenant_id)
  VALUES (p_slot_id, v_user, 'PENDING_PAYMENT', v_slot.price, now() + interval '20 minutes', 'system', public.tenant_id())
  RETURNING * INTO v_book;
  INSERT INTO public.audit_log (user_id, action, entity_type, entity_id, meta)
  VALUES (v_user, 'book_slot', 'bookings', v_book.id,
          jsonb_build_object('slot_id', p_slot_id, 'opt_in', p_opt_in));
  RETURN v_book;
END;
$$;

REVOKE ALL ON FUNCTION public.book_slot(bigint, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.book_slot(bigint, boolean) TO authenticated;

-- 2. Update transition_booking_status with hardened is_admin() cancel-path
CREATE OR REPLACE FUNCTION public.transition_booking_status(
  p_booking_id bigint,
  p_new_status public.booking_status,
  p_action text,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
) RETURNS public.bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_book public.bookings;
  v_old_status public.booking_status;
BEGIN
  SELECT * INTO v_book FROM public.bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_book IS NULL THEN RAISE EXCEPTION 'BOOKING_NOT_FOUND'; END IF;
  IF v_book.status = p_new_status THEN RETURN v_book; END IF;

  -- SECURITY DEFINER must never widen access: re-assert gates here.
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    IF v_book.user_id <> auth.uid() THEN
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
    END IF;
    IF p_new_status NOT IN ('CANCELLED') THEN
      RAISE EXCEPTION 'FORBIDDEN: users can only cancel bookings' USING ERRCODE = '42501';
    END IF;
  END IF;

  v_old_status := v_book.status;
  UPDATE public.bookings
     SET status = p_new_status,
         locked_until = CASE WHEN p_new_status = 'PENDING_PAYMENT' THEN locked_until ELSE NULL END,
         updated_at = now()
   WHERE id = p_booking_id
   RETURNING * INTO v_book;

  INSERT INTO public.audit_log (user_id, action, entity_type, entity_id, meta)
  VALUES (auth.uid(), p_action, 'bookings', p_booking_id,
          jsonb_build_object('old_status', v_old_status, 'new_status', p_new_status,
                             'reason', p_reason, 'slot_id', v_book.slot_id) || p_metadata);
  RETURN v_book;
END;
$$;

REVOKE ALL ON FUNCTION public.transition_booking_status(bigint, public.booking_status, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transition_booking_status(bigint, public.booking_status, text, text, jsonb) TO authenticated, service_role;

-- 3. Storage RLS Guard catching ONLY insufficient_privilege
DO $$
BEGIN
  ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
EXCEPTION
  WHEN insufficient_privilege THEN NULL;
END $$;
