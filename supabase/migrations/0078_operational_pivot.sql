-- ==============================================================================
-- 0078_operational_pivot.sql
-- Church Platform Administrative & Product Pivot (Three Operational Tracks)
-- 1. Track 1 (Sacraments): Category & required official documents on event_types
-- 2. Track 2 (Activities): Event types classification & extra services scoping
-- 3. Quick Cash Collection RPC: admin_quick_cash_collect for church cashier
-- 4. Track 3 (Sunday School): get_class_visitation_list for fast pastoral follow-up
-- ==============================================================================

-- 1. Alter event_types for Category & Required Documents
ALTER TABLE public.event_types
ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'SACRAMENT' CHECK (category IN ('SACRAMENT', 'ACTIVITY'));

ALTER TABLE public.event_types
ADD COLUMN IF NOT EXISTS required_documents_ar TEXT[] DEFAULT '{}';

-- 2. Backfill existing event_types categories and required documents
UPDATE public.event_types
SET category = 'SACRAMENT',
    required_documents_ar = ARRAY['شهادة خلو موانع', 'شهادة دورة المشورة الأسرية', 'موافقة أب الاعتراف']
WHERE name_ar LIKE '%إكليل%' OR name_ar LIKE '%زفاف%' OR name_ar LIKE '%زواج%';

UPDATE public.event_types
SET category = 'SACRAMENT',
    required_documents_ar = ARRAY['شهادة ميلاد الطفل', 'موافقة الأب والأم']
WHERE name_ar LIKE '%معمودية%' OR name_ar LIKE '%عماد%';

UPDATE public.event_types
SET category = 'SACRAMENT',
    required_documents_ar = ARRAY['تصريح الدفن الرسمي', 'شهادة الوفاة']
WHERE name_ar LIKE '%جناز%' OR name_ar LIKE '%عزاء%';

UPDATE public.event_types
SET category = 'SACRAMENT',
    required_documents_ar = ARRAY['شهادة خلو موانع']
WHERE name_ar LIKE '%خطوبة%' OR name_ar LIKE '%خطبة%';

UPDATE public.event_types
SET category = 'ACTIVITY',
    required_documents_ar = '{}'
WHERE name_ar LIKE '%رحلة%' OR name_ar LIKE '%مؤتمر%' OR name_ar LIKE '%نادي%' OR name_ar LIKE '%صيفي%';

-- 3. Stored Procedure: admin_quick_cash_collect
CREATE OR REPLACE FUNCTION public.admin_quick_cash_collect(
  p_booking_id UUID,
  p_amount_piastres BIGINT,
  p_collector_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_booking public.event_bookings;
  v_new_paid BIGINT;
  v_new_status public.event_booking_status;
  v_audit_id BIGINT;
  v_customer_phone TEXT;
  v_event_name TEXT;
BEGIN
  -- Authorization Guard
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING errcode = '28000';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;

  IF p_booking_id IS NULL OR p_amount_piastres IS NULL OR p_amount_piastres <= 0 THEN
    RAISE EXCEPTION 'BAD_REQUEST' USING errcode = 'P0001';
  END IF;

  -- Lock booking row
  SELECT * INTO v_booking
  FROM public.event_bookings
  WHERE id = p_booking_id AND tenant_id = public.tenant_id()
  FOR UPDATE;

  IF v_booking.id IS NULL OR v_booking.status IN ('CANCELLED', 'REJECTED') THEN
    RAISE EXCEPTION 'BAD_REQUEST' USING errcode = 'P0001';
  END IF;

  v_new_paid := COALESCE(v_booking.paid_amount_piastres, 0) + p_amount_piastres;
  
  -- Advance status to PAID if fully paid or marked paid
  IF v_new_paid >= v_booking.total_price_piastres THEN
    v_new_status := 'PAID';
  ELSE
    v_new_status := 'PENDING_PAYMENT';
  END IF;

  UPDATE public.event_bookings
  SET paid_amount_piastres = v_new_paid,
      status = v_new_status,
      updated_at = now()
  WHERE id = p_booking_id
  RETURNING * INTO v_booking;

  -- Insert immutable payment audit log
  INSERT INTO public.payment_audit_logs (
    booking_id,
    amount_piastres,
    method,
    recorded_by,
    action,
    notes,
    tenant_id
  ) VALUES (
    p_booking_id,
    p_amount_piastres,
    'CASH',
    v_user,
    'CASH_COLLECTED',
    COALESCE(p_collector_note, 'تحصيل نقدي فوري بالخزينة'),
    public.tenant_id()
  ) RETURNING id INTO v_audit_id;

  -- General Audit log
  INSERT INTO public.audit_log (user_id, action, entity_type, entity_id, meta)
  VALUES (
    v_user,
    'admin_quick_cash_collect',
    'event_bookings',
    0,
    jsonb_build_object(
      'event_booking_id', p_booking_id,
      'amount_piastres', p_amount_piastres,
      'total_paid', v_new_paid,
      'status', v_new_status,
      'collector_note', p_collector_note
    )
  );

  -- Retrieve event details for WhatsApp template
  SELECT name_ar INTO v_event_name FROM public.event_types WHERE id = v_booking.event_type_id;
  SELECT phone INTO v_customer_phone FROM public.users WHERE id = v_booking.customer_id;

  -- WhatsApp Notification Outbox
  IF v_customer_phone IS NOT NULL THEN
    INSERT INTO public.event_outbox (handler_type, payload, tenant_id)
    VALUES (
      'WHATSAPP',
      jsonb_build_object(
        'phone', v_customer_phone,
        'template_name', 'event_booking_payment_received',
        'params', jsonb_build_object(
          'booking_id', v_booking.id,
          'event_name', COALESCE(v_event_name, 'مناسبة كنسية'),
          'amount_paid_piastres', p_amount_piastres,
          'total_paid_piastres', v_new_paid,
          'remaining_piastres', GREATEST(0, v_booking.total_price_piastres - v_new_paid)
        )
      ),
      public.tenant_id()
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'audit_id', v_audit_id,
    'booking_id', p_booking_id,
    'amount_piastres', p_amount_piastres,
    'total_paid_piastres', v_new_paid,
    'status', v_new_status
  );
END;
$$;

-- Harden privileges for admin_quick_cash_collect
REVOKE ALL ON FUNCTION public.admin_quick_cash_collect(UUID, BIGINT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_quick_cash_collect(UUID, BIGINT, TEXT) TO authenticated, service_role;


-- 4. Stored Procedure: get_class_visitation_list (Sunday School Visitation Track)
CREATE OR REPLACE FUNCTION public.get_class_visitation_list(
  p_class_id UUID,
  p_session_date DATE DEFAULT NULL
)
RETURNS TABLE (
  student_id UUID,
  student_name_ar TEXT,
  phone TEXT,
  parent_phone TEXT,
  notes TEXT,
  session_date DATE,
  attendance_status TEXT,
  last_attended_date DATE,
  consecutive_absences INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_target_date DATE;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING errcode = '28000';
  END IF;

  IF p_class_id IS NULL THEN
    RAISE EXCEPTION 'BAD_REQUEST' USING errcode = 'P0001';
  END IF;

  -- Authorization: Admin or Servant assigned to class
  IF NOT (public.is_admin() OR public.is_class_servant(p_class_id)) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;

  -- Determine target session date (specified date, or latest recorded session date for this class)
  IF p_session_date IS NOT NULL THEN
    v_target_date := p_session_date;
  ELSE
    SELECT COALESCE(
      (SELECT MAX(s.session_date) FROM public.sunday_school_sessions s WHERE s.class_id = p_class_id AND s.tenant_id = public.tenant_id()),
      (SELECT MAX(a.session_date) FROM public.sunday_school_attendance a WHERE a.class_id = p_class_id AND a.tenant_id = public.tenant_id()),
      CURRENT_DATE
    ) INTO v_target_date;
  END IF;

  RETURN QUERY
  WITH last_attendance AS (
    SELECT
      ssa.student_id,
      MAX(ssa.session_date) AS last_present_date
    FROM public.sunday_school_attendance ssa
    WHERE ssa.class_id = p_class_id
      AND ssa.status = 'PRESENT'
      AND ssa.session_date <= v_target_date
      AND ssa.tenant_id = public.tenant_id()
    GROUP BY ssa.student_id
  ),
  absence_counts AS (
    SELECT
      ssa.student_id,
      COUNT(*)::INT AS total_absences_recent
    FROM public.sunday_school_attendance ssa
    WHERE ssa.class_id = p_class_id
      AND ssa.status IN ('ABSENT', 'EXCUSED')
      AND ssa.session_date <= v_target_date
      AND ssa.session_date > COALESCE(
        (SELECT la.last_present_date FROM last_attendance la WHERE la.student_id = ssa.student_id),
        '2000-01-01'::DATE
      )
      AND ssa.tenant_id = public.tenant_id()
    GROUP BY ssa.student_id
  )
  SELECT
    st.id AS student_id,
    st.full_name_ar AS student_name_ar,
    COALESCE(st.phone, '') AS phone,
    COALESCE(st.parent_phone, '') AS parent_phone,
    COALESCE(st.notes, '') AS notes,
    v_target_date AS session_date,
    COALESCE(att.status, 'ABSENT') AS attendance_status,
    la.last_present_date AS last_attended_date,
    GREATEST(1, COALESCE(ac.total_absences_recent, 1)) AS consecutive_absences
  FROM public.sunday_school_students st
  LEFT JOIN public.sunday_school_attendance att
    ON att.student_id = st.id
   AND att.session_date = v_target_date
   AND att.tenant_id = public.tenant_id()
  LEFT JOIN last_attendance la ON la.student_id = st.id
  LEFT JOIN absence_counts ac ON ac.student_id = st.id
  WHERE st.class_id = p_class_id
    AND st.is_active = true
    AND st.tenant_id = public.tenant_id()
    AND (att.status IS NULL OR att.status IN ('ABSENT', 'EXCUSED'))
  ORDER BY st.full_name_ar ASC;
END;
$$;

-- Harden privileges for get_class_visitation_list
REVOKE ALL ON FUNCTION public.get_class_visitation_list(UUID, DATE) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_class_visitation_list(UUID, DATE) TO authenticated, service_role;
