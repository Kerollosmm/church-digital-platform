-- 0059_tenant_scaffolding.sql
-- Tighten tenant scaffolding across analytics, audit log, and whatsapp optins

-- 1. payments_monthly composite primary key (tenant_id, month)
ALTER TABLE public.payments_monthly
  DROP CONSTRAINT IF EXISTS payments_monthly_pkey,
  ADD PRIMARY KEY (tenant_id, month);

-- 2. Scoped materialize_analytics RPC
CREATE OR REPLACE FUNCTION public.materialize_analytics()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE m date := (date_trunc('month', now() AT TIME ZONE 'Africa/Cairo'))::date;
BEGIN
  DELETE FROM public.slot_utilization_monthly WHERE month = m;
  INSERT INTO public.slot_utilization_monthly (tenant_id, service_id, month, slots_total, slots_booked, utilization_pct)
  SELECT
    s.tenant_id,
    s.id, m,
    count(DISTINCT sl.id),
    count(DISTINCT b.slot_id),
    CASE WHEN count(DISTINCT sl.id) = 0 THEN 0
         ELSE round(100.0 * count(DISTINCT b.slot_id) / count(DISTINCT sl.id), 2) END
  FROM public.services s
  LEFT JOIN public.service_slots sl ON sl.service_id = s.id
    AND sl.starts_at AT TIME ZONE 'Africa/Cairo' >= m
    AND sl.starts_at AT TIME ZONE 'Africa/Cairo' < m + interval '1 month'
  LEFT JOIN public.bookings b ON b.slot_id = sl.id AND b.status IN ('AWAITING_CALL','CONFIRMED','COMPLETED')
  GROUP BY s.tenant_id, s.id;

  DELETE FROM public.payments_monthly WHERE month = m;
  INSERT INTO public.payments_monthly (tenant_id, month, total_paid, total_refunded, count_paid)
  SELECT
    p.tenant_id,
    m,
    COALESCE(sum(amount) FILTER (WHERE status = 'PAID'), 0),
    COALESCE(sum(amount) FILTER (WHERE status = 'REFUNDED'), 0),
    count(*) FILTER (WHERE status = 'PAID')
  FROM public.payments p
  WHERE p.created_at AT TIME ZONE 'Africa/Cairo' >= m
  GROUP BY p.tenant_id;

  DELETE FROM public.bookings_monthly WHERE month = m;
  WITH agg AS (
    SELECT sl.tenant_id, sl.service_id, b.status, count(*) AS cnt
    FROM public.bookings b
    JOIN public.service_slots sl ON sl.id = b.slot_id
    WHERE b.created_at AT TIME ZONE 'Africa/Cairo' >= m
      AND b.created_at AT TIME ZONE 'Africa/Cairo' < m + interval '1 month'
    GROUP BY sl.tenant_id, sl.service_id, b.status
  ),
  by_svc AS (
    SELECT tenant_id, service_id, sum(cnt) AS total, jsonb_object_agg(status, cnt) AS status_map
    FROM agg GROUP BY tenant_id, service_id
  )
  INSERT INTO public.bookings_monthly (tenant_id, service_id, month, bookings_total, by_status)
  SELECT s.tenant_id, s.id, m, COALESCE(bs.total, 0), COALESCE(bs.status_map, '{}'::jsonb)
  FROM public.services s
  LEFT JOIN by_svc bs ON bs.service_id = s.id AND bs.tenant_id = s.tenant_id;
END;
$$;

-- 3. audit_log tenant_id column and policy hardening
ALTER TABLE public.audit_log
  ADD COLUMN IF NOT EXISTS tenant_id BIGINT NOT NULL DEFAULT public.tenant_id();

ALTER TABLE public.audit_log
  ALTER COLUMN tenant_id SET DEFAULT public.tenant_id(),
  ALTER COLUMN tenant_id SET NOT NULL;

DROP POLICY IF EXISTS "audit_log_admin_select" ON public.audit_log;
CREATE POLICY "audit_log_admin_select" ON public.audit_log
  FOR SELECT TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id());

-- 4. whatsapp_optins tenant_id and composite primary key
UPDATE public.whatsapp_optins SET tenant_id = public.tenant_id() WHERE tenant_id IS NULL;

ALTER TABLE public.whatsapp_optins
  ALTER COLUMN tenant_id SET DEFAULT public.tenant_id(),
  ALTER COLUMN tenant_id SET NOT NULL;

ALTER TABLE public.whatsapp_optins
  DROP CONSTRAINT IF EXISTS whatsapp_optins_pkey,
  ADD PRIMARY KEY (tenant_id, phone);

DROP POLICY IF EXISTS "p0_admin_all" ON public.whatsapp_optins;
CREATE POLICY "p0_admin_all" ON public.whatsapp_optins
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "whatsapp_optins read own" ON public.whatsapp_optins;
CREATE POLICY "whatsapp_optins read own" ON public.whatsapp_optins
  FOR SELECT TO authenticated
  USING (
    ((phone = (SELECT phone FROM public.users WHERE id = auth.uid())) OR public.is_admin())
    AND tenant_id = public.tenant_id()
  );

-- 5. Update book_slot and manual_book to target composite PK (tenant_id, phone) on whatsapp_optins
CREATE OR REPLACE FUNCTION public.book_slot(
  p_slot_id bigint,
  p_opt_in boolean DEFAULT false,
  p_idempotency_key uuid DEFAULT NULL
)
RETURNS public.bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_role text := public.current_user_role();
  v_slot public.service_slots;
  v_mine integer;
  v_active_count integer;
  v_booking public.bookings;
  v_user_phone text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '28000';
  END IF;

  v_role := public.current_user_role();
  IF v_role NOT IN ('USER', 'ADMIN', 'SUPER_ADMIN', 'PARISHIONER') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  -- Idempotency check
  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_booking
    FROM public.bookings
    WHERE notes = p_idempotency_key::text
      AND user_id = v_user_id;
    IF FOUND THEN
      RETURN v_booking;
    END IF;
  END IF;

  -- Lock slot row for concurrency control
  SELECT * INTO v_slot
  FROM public.service_slots
  WHERE id = p_slot_id AND deleted_at IS NULL
  FOR UPDATE;

  IF v_slot.id IS NULL THEN
    RAISE EXCEPTION 'SLOT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_slot.status = 'CLOSED' OR v_slot.starts_at <= now() THEN
    RAISE EXCEPTION 'SLOT_UNAVAILABLE' USING ERRCODE = 'P0001';
  END IF;

  -- Max 3 active bookings per user
  SELECT count(*) INTO v_mine
  FROM public.bookings
  WHERE user_id = v_user_id AND status IN ('PENDING_PAYMENT', 'AWAITING_CALL', 'CONFIRMED');
  IF v_mine >= 3 THEN
    RAISE EXCEPTION 'TOO_MANY_ACTIVE_BOOKINGS' USING ERRCODE = 'P0001';
  END IF;

  -- Duplicate booking check
  IF EXISTS (
    SELECT 1 FROM public.bookings
    WHERE slot_id = p_slot_id AND user_id = v_user_id
      AND status IN ('PENDING_PAYMENT', 'AWAITING_CALL', 'CONFIRMED')
  ) THEN
    RAISE EXCEPTION 'ALREADY_BOOKED_SLOT' USING ERRCODE = 'P0001';
  END IF;

  -- Compute active booking count dynamically
  v_active_count := public.active_booking_count(p_slot_id);
  IF v_active_count >= v_slot.capacity THEN
    RAISE EXCEPTION 'SLOT_FULL' USING ERRCODE = 'P0001';
  END IF;

  -- Handle WhatsApp opt-in targeting composite PK (tenant_id, phone)
  IF p_opt_in THEN
    SELECT phone INTO v_user_phone FROM public.users WHERE id = v_user_id;
    IF v_user_phone IS NOT NULL THEN
      INSERT INTO public.whatsapp_optins (tenant_id, phone, source)
      VALUES (public.tenant_id(), v_user_phone, 'BOOKING')
      ON CONFLICT (tenant_id, phone) DO UPDATE SET consented_at = now();
    END IF;
  END IF;

  -- Insert booking
  INSERT INTO public.bookings (
    tenant_id,
    slot_id,
    user_id,
    status,
    paid_amount,
    notes,
    locked_until,
    created_by
  ) VALUES (
    public.tenant_id(),
    p_slot_id,
    v_user_id,
    'PENDING_PAYMENT',
    COALESCE(v_slot.price, 0),
    p_idempotency_key::text,
    now() + interval '20 minutes',
    'system'
  )
  RETURNING * INTO v_booking;

  -- Audit log entry
  INSERT INTO public.audit_log (tenant_id, user_id, action, entity_type, entity_id, meta)
  VALUES (
    public.tenant_id(),
    v_user_id,
    'book_slot',
    'bookings',
    v_booking.id,
    jsonb_build_object('slot_id', p_slot_id, 'opt_in', p_opt_in)
  );

  -- Emit SLOT_EXHAUSTED realtime signal if slot is now fully booked
  IF (v_active_count + 1) >= v_slot.capacity THEN
    PERFORM pg_notify(
      'realtime:event_inventory',
      jsonb_build_object(
        'topic', 'slot:' || p_slot_id::text || ':availability',
        'event', 'SLOT_EXHAUSTED',
        'payload', jsonb_build_object('slot_id', p_slot_id, 'status', 'BOOKED')
      )::text
    );
  END IF;

  RETURN v_booking;
END;
$$;

REVOKE ALL ON FUNCTION public.book_slot(bigint, boolean, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.book_slot(bigint, boolean, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.manual_book(
  p_slot_id bigint,
  p_phone text,
  p_opt_in boolean DEFAULT false,
  p_notes text DEFAULT NULL::text
)
RETURNS bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_role text := public.current_user_role();
  v_user uuid;
  v_book public.bookings;
  v_slot public.service_slots;
BEGIN
  IF v_role NOT IN ('ADMIN','PRIEST','SUPER_ADMIN') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  SELECT id INTO v_user FROM public.users WHERE phone = p_phone;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.service_slots WHERE id = p_slot_id AND status <> 'CLOSED' AND starts_at > now()) THEN
    RAISE EXCEPTION 'SLOT_UNAVAILABLE';
  END IF;
  IF p_opt_in THEN
    INSERT INTO public.whatsapp_optins (tenant_id, phone, source)
    VALUES (public.tenant_id(), p_phone, 'MANUAL')
    ON CONFLICT (tenant_id, phone) DO UPDATE SET consented_at = now();
  END IF;
  BEGIN
    SELECT * INTO v_slot FROM public.service_slots WHERE id = p_slot_id FOR UPDATE;
    IF v_slot IS NULL OR v_slot.status = 'CLOSED' THEN
      RAISE EXCEPTION 'SLOT_TAKEN';
    END IF;
    IF public.active_booking_count(p_slot_id, true) >= v_slot.capacity THEN
      RAISE EXCEPTION 'SLOT_TAKEN';
    END IF;
    INSERT INTO public.bookings (slot_id, user_id, status, paid_amount, created_by, notes, tenant_id)
    VALUES (p_slot_id, v_user, 'CONFIRMED', v_slot.price, 'employee', coalesce(p_notes, 'manual'), public.tenant_id())
    RETURNING * INTO v_book;
  END;
  INSERT INTO public.audit_log (tenant_id, user_id, action, entity_type, entity_id, meta)
  VALUES (public.tenant_id(), auth.uid(), 'manual_book', 'bookings', v_book.id,
          jsonb_build_object('slot_id', p_slot_id, 'phone', p_phone, 'opt_in', p_opt_in));
  RETURN v_book;
END;
$$;
