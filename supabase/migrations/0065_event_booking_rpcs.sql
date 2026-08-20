-- 0065_event_booking_rpcs.sql
-- Spec 008 Event Booking RPCs: Submission, Review Queue (Confirm/Reject), Cash Payment Audit, SuperAdmin Catalog Management.

CREATE OR REPLACE FUNCTION public.submit_event_booking(
  p_event_type_id BIGINT,
  p_requested_time TIMESTAMPTZ,
  p_extras JSONB DEFAULT '[]'::JSONB,
  p_notes TEXT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID;
  v_user_phone TEXT;
  v_base_price BIGINT;
  v_extras_total BIGINT := 0;
  v_booking_id BIGINT;
  v_item JSONB;
  v_extra_id BIGINT;
  v_qty INT;
  v_unit_price BIGINT;
  v_extra_item_total BIGINT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION '{"error": "UNAUTHORIZED", "message_ar": "يجب تسجيل الدخول أولاً"}' USING ERRCODE = '42501';
  END IF;

  SELECT phone INTO v_user_phone FROM public.users WHERE id = v_user_id;

  SELECT COALESCE(base_price_piastres, 0) INTO v_base_price
  FROM public.event_types
  WHERE id = p_event_type_id AND is_active = true AND tenant_id = public.tenant_id();

  IF v_base_price IS NULL THEN
    RAISE EXCEPTION '{"error": "BAD_REQUEST", "message_ar": "نوع المناسبة غير متاح"}' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.bookings (
    tenant_id,
    user_id,
    slot_id,
    status,
    notes,
    total_price_piastres,
    paid_amount_piastres,
    created_at,
    updated_at
  ) VALUES (
    public.tenant_id(),
    v_user_id,
    NULL,
    'SUBMITTED'::booking_status,
    p_notes,
    v_base_price,
    0,
    now(),
    now()
  ) RETURNING id INTO v_booking_id;

  IF p_extras IS NOT NULL AND jsonb_array_length(p_extras) > 0 THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_extras) LOOP
      v_extra_id := (v_item->>'extra_service_id')::BIGINT;
      v_qty := COALESCE((v_item->>'quantity')::INT, 1);

      SELECT unit_price_piastres INTO v_unit_price
      FROM public.extra_services
      WHERE id = v_extra_id AND is_active = true AND tenant_id = public.tenant_id();

      IF v_unit_price IS NOT NULL THEN
        v_extra_item_total := v_unit_price * v_qty;
        v_extras_total := v_extras_total + v_extra_item_total;

        INSERT INTO public.booking_extra_services (
          tenant_id,
          booking_id,
          extra_service_id,
          unit_price_snapshot_piastres,
          quantity,
          total_price_snapshot_piastres
        ) VALUES (
          public.tenant_id(),
          v_booking_id,
          v_extra_id,
          v_unit_price,
          v_qty,
          v_extra_item_total
        );
      END IF;
    END LOOP;
  END IF;

  UPDATE public.bookings
  SET total_price_piastres = v_base_price + v_extras_total
  WHERE id = v_booking_id;

  INSERT INTO public.whatsapp_outbox (
    tenant_id,
    phone,
    template_name,
    payload,
    event_type,
    status
  ) VALUES (
    public.tenant_id(),
    COALESCE(v_user_phone, ''),
    'EVENT_SUBMISSION_RECEIVED',
    jsonb_build_object(
      'booking_id', v_booking_id,
      'requested_time', p_requested_time,
      'total_price_piastres', v_base_price + v_extras_total
    ),
    'EVENT_SUBMISSION_RECEIVED',
    'PENDING'
  );

  RETURN v_booking_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_confirm_booking(
  p_booking_id BIGINT,
  p_venue_id BIGINT,
  p_confirmed_start TIMESTAMPTZ,
  p_duration_minutes INT DEFAULT 120
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_phone TEXT;
  v_confirmed_end TIMESTAMPTZ;
  v_total_price BIGINT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION '{"error": "FORBIDDEN", "message_ar": "غير مصرح لك بتأكيد حجز المناسبة"}' USING ERRCODE = '42501';
  END IF;

  v_confirmed_end := p_confirmed_start + (p_duration_minutes || ' minutes')::INTERVAL;

  SELECT u.phone, b.total_price_piastres INTO v_user_phone, v_total_price
  FROM public.bookings b
  JOIN public.users u ON b.user_id = u.id
  WHERE b.id = p_booking_id AND b.tenant_id = public.tenant_id();

  IF v_total_price IS NULL THEN
    RAISE EXCEPTION '{"error": "BAD_REQUEST", "message_ar": "طلب الحجز غير موجود"}' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.event_resource_bookings (
    tenant_id,
    booking_id,
    resource_id,
    booking_period,
    is_active
  ) VALUES (
    public.tenant_id(),
    p_booking_id,
    p_venue_id,
    tstzrange(p_confirmed_start, v_confirmed_end),
    true
  );

  UPDATE public.bookings
  SET status = CASE WHEN v_total_price > 0 THEN 'PENDING_PAYMENT'::booking_status ELSE 'CONFIRMED'::booking_status END,
      updated_at = now()
  WHERE id = p_booking_id;

  INSERT INTO public.whatsapp_outbox (
    tenant_id,
    phone,
    template_name,
    payload,
    event_type,
    status
  ) VALUES (
    public.tenant_id(),
    COALESCE(v_user_phone, ''),
    'EVENT_BOOKING_CONFIRMED',
    jsonb_build_object(
      'booking_id', p_booking_id,
      'venue_id', p_venue_id,
      'confirmed_start', p_confirmed_start,
      'total_price_piastres', v_total_price
    ),
    'EVENT_BOOKING_CONFIRMED',
    'PENDING'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reject_booking(
  p_booking_id BIGINT,
  p_rejection_reason TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_phone TEXT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION '{"error": "FORBIDDEN", "message_ar": "غير مصرح لك بفض طلب المناسبة"}' USING ERRCODE = '42501';
  END IF;

  IF p_rejection_reason IS NULL OR trim(p_rejection_reason) = '' THEN
    RAISE EXCEPTION '{"error": "BAD_REQUEST", "message_ar": "يجب كتابة سبب الرفض"}' USING ERRCODE = 'P0001';
  END IF;

  SELECT u.phone INTO v_user_phone
  FROM public.bookings b
  JOIN public.users u ON b.user_id = u.id
  WHERE b.id = p_booking_id AND b.tenant_id = public.tenant_id();

  UPDATE public.bookings
  SET status = 'REJECTED'::booking_status,
      notes = COALESCE(notes, '') || ' [سبب الرفض: ' || p_rejection_reason || ']',
      updated_at = now()
  WHERE id = p_booking_id;

  UPDATE public.event_resource_bookings
  SET is_active = false
  WHERE booking_id = p_booking_id;

  INSERT INTO public.whatsapp_outbox (
    tenant_id,
    phone,
    template_name,
    payload,
    event_type,
    status
  ) VALUES (
    public.tenant_id(),
    COALESCE(v_user_phone, ''),
    'EVENT_BOOKING_REJECTED',
    jsonb_build_object(
      'booking_id', p_booking_id,
      'rejection_reason', p_rejection_reason
    ),
    'EVENT_BOOKING_REJECTED',
    'PENDING'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_record_cash_payment(
  p_booking_id BIGINT,
  p_amount_piastres BIGINT,
  p_receipt_ref TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_admin_id UUID;
  v_total_price BIGINT;
  v_curr_paid BIGINT;
  v_new_paid BIGINT;
  v_audit_id BIGINT;
  v_new_status booking_status;
BEGIN
  v_admin_id := auth.uid();
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION '{"error": "FORBIDDEN", "message_ar": "غير مصرح لك بتسجيل دفعة نقدية"}' USING ERRCODE = '42501';
  END IF;

  IF p_amount_piastres <= 0 THEN
    RAISE EXCEPTION '{"error": "BAD_REQUEST", "message_ar": "المبلغ يجب أن يكون أكبر من صفر"}' USING ERRCODE = 'P0001';
  END IF;

  SELECT total_price_piastres, COALESCE(paid_amount_piastres, 0)
  INTO v_total_price, v_curr_paid
  FROM public.bookings
  WHERE id = p_booking_id AND tenant_id = public.tenant_id()
  FOR UPDATE;

  IF v_total_price IS NULL THEN
    RAISE EXCEPTION '{"error": "BAD_REQUEST", "message_ar": "الحجز غير موجود"}' USING ERRCODE = 'P0001';
  END IF;

  v_new_paid := v_curr_paid + p_amount_piastres;
  IF v_new_paid >= v_total_price THEN
    v_new_status := 'PAID'::booking_status;
  ELSE
    v_new_status := 'PARTIALLY_PAID'::booking_status;
  END IF;

  INSERT INTO public.payment_audit_logs (
    tenant_id,
    booking_id,
    recorded_by,
    payment_method,
    amount_piastres,
    receipt_reference,
    notes
  ) VALUES (
    public.tenant_id(),
    p_booking_id,
    v_admin_id,
    'CASH',
    p_amount_piastres,
    p_receipt_ref,
    p_notes
  ) RETURNING id INTO v_audit_id;

  UPDATE public.bookings
  SET paid_amount_piastres = v_new_paid,
      status = v_new_status,
      updated_at = now()
  WHERE id = p_booking_id;

  RETURN v_audit_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.superadmin_upsert_event_type(
  p_id BIGINT,
  p_name_ar TEXT,
  p_base_price_piastres BIGINT,
  p_is_active BOOLEAN DEFAULT true
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_res_id BIGINT;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION '{"error": "FORBIDDEN", "message_ar": "غير مصرح لك بتهيئة دليل المناسبات"}' USING ERRCODE = '42501';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.event_types (tenant_id, name_ar, base_price_piastres, is_active)
    VALUES (public.tenant_id(), p_name_ar, p_base_price_piastres, p_is_active)
    RETURNING id INTO v_res_id;
  ELSE
    UPDATE public.event_types
    SET name_ar = p_name_ar,
        base_price_piastres = p_base_price_piastres,
        is_active = p_is_active,
        updated_at = now()
    WHERE id = p_id AND tenant_id = public.tenant_id()
    RETURNING id INTO v_res_id;
  END IF;

  RETURN v_res_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.superadmin_upsert_extra_service(
  p_id BIGINT,
  p_name_ar TEXT,
  p_unit_price_piastres BIGINT,
  p_is_quantity_based BOOLEAN DEFAULT false,
  p_is_active BOOLEAN DEFAULT true
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_res_id BIGINT;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION '{"error": "FORBIDDEN", "message_ar": "غير مصرح لك بتهيئة دليل الخدمات الإضافية"}' USING ERRCODE = '42501';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.extra_services (tenant_id, name_ar, unit_price_piastres, is_quantity_based, is_active)
    VALUES (public.tenant_id(), p_name_ar, p_unit_price_piastres, p_is_quantity_based, p_is_active)
    RETURNING id INTO v_res_id;
  ELSE
    UPDATE public.extra_services
    SET name_ar = p_name_ar,
        unit_price_piastres = p_unit_price_piastres,
        is_quantity_based = p_is_quantity_based,
        is_active = p_is_active,
        updated_at = now()
    WHERE id = p_id AND tenant_id = public.tenant_id()
    RETURNING id INTO v_res_id;
  END IF;

  RETURN v_res_id;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_event_booking(BIGINT, TIMESTAMPTZ, JSONB, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_confirm_booking(BIGINT, BIGINT, TIMESTAMPTZ, INT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_reject_booking(BIGINT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_record_cash_payment(BIGINT, BIGINT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.superadmin_upsert_event_type(BIGINT, TEXT, BIGINT, BOOLEAN) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.superadmin_upsert_extra_service(BIGINT, TEXT, BIGINT, BOOLEAN, BOOLEAN) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.submit_event_booking(BIGINT, TIMESTAMPTZ, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_confirm_booking(BIGINT, BIGINT, TIMESTAMPTZ, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reject_booking(BIGINT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_record_cash_payment(BIGINT, BIGINT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.superadmin_upsert_event_type(BIGINT, TEXT, BIGINT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.superadmin_upsert_extra_service(BIGINT, TEXT, BIGINT, BOOLEAN, BOOLEAN) TO authenticated;
