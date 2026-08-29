-- ==============================================================================
-- 0075_priest_hall_allocation.sql
-- Spec 009: Smart Priest & Hall Allocation Matrix
-- Priest schedule management, concurrent range exclusion constraints,
-- atomic priest and venue assignment RPC, and priest availability lookup.
-- ==============================================================================

-- 1. Extension
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 2. Alter priests table to ensure phone and rank columns exist
ALTER TABLE public.priests ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.priests ADD COLUMN IF NOT EXISTS rank TEXT DEFAULT 'PRIEST';

-- 3. Priest Schedules Table
CREATE TABLE IF NOT EXISTS public.priest_schedules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  priest_id BIGINT NOT NULL REFERENCES public.priests(id) ON DELETE CASCADE,
  schedule_range TSTZRANGE NOT NULL,
  schedule_type TEXT NOT NULL DEFAULT 'EVENT_BOOKING',
  booking_id UUID REFERENCES public.event_bookings(id) ON DELETE SET NULL,
  notes TEXT,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT no_overlapping_priest_schedules EXCLUDE USING gist (
    priest_id WITH =,
    schedule_range WITH &&
  )
);

-- 4. Alter event_bookings for assigned_priest_id and GiST exclusion constraint
ALTER TABLE public.event_bookings
ADD COLUMN IF NOT EXISTS assigned_priest_id BIGINT REFERENCES public.priests(id) ON DELETE SET NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'no_overlapping_priest_events'
  ) THEN
    ALTER TABLE public.event_bookings
    ADD CONSTRAINT no_overlapping_priest_events
    EXCLUDE USING gist (
      assigned_priest_id WITH =,
      booking_range WITH &&
    )
    WHERE (assigned_priest_id IS NOT NULL AND status IN ('SUBMITTED', 'CONFIRMED', 'PENDING_PAYMENT', 'PAID'));
  END IF;
END $$;

-- 5. Indexes
CREATE INDEX IF NOT EXISTS idx_priest_schedules_priest ON public.priest_schedules(priest_id);
CREATE INDEX IF NOT EXISTS idx_priest_schedules_range ON public.priest_schedules USING gist (schedule_range);
CREATE INDEX IF NOT EXISTS idx_priest_schedules_booking ON public.priest_schedules(booking_id);
CREATE INDEX IF NOT EXISTS idx_priest_schedules_tenant ON public.priest_schedules(tenant_id);
CREATE INDEX IF NOT EXISTS idx_event_bookings_assigned_priest ON public.event_bookings(assigned_priest_id);

-- 6. Enable RLS on priest_schedules (Mandatory 2 statements per AGENTS.md)
ALTER TABLE public.priest_schedules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read priest schedules" ON public.priest_schedules;
CREATE POLICY "Authenticated read priest schedules" ON public.priest_schedules
  FOR SELECT TO anon, authenticated
  USING (tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Admin manage priest schedules" ON public.priest_schedules;
CREATE POLICY "Admin manage priest schedules" ON public.priest_schedules
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

-- 7. Permissions & Grants
REVOKE INSERT, UPDATE, DELETE ON public.priest_schedules FROM anon, authenticated;
GRANT SELECT ON public.priest_schedules TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.priest_schedules TO service_role;

-- 8. Stored Procedure: admin_assign_priest_and_venue
CREATE OR REPLACE FUNCTION public.admin_assign_priest_and_venue(
  p_booking_id UUID,
  p_venue_id UUID,
  p_priest_id BIGINT,
  p_override_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_booking public.event_bookings;
  v_venue public.venues_resources;
  v_priest public.priests;
  v_customer_phone TEXT;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING errcode = '28000';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;

  IF p_booking_id IS NULL OR p_venue_id IS NULL OR p_priest_id IS NULL THEN
    RAISE EXCEPTION 'BAD_REQUEST';
  END IF;

  SELECT * INTO v_booking
  FROM public.event_bookings
  WHERE id = p_booking_id AND tenant_id = public.tenant_id()
  FOR UPDATE;

  IF v_booking.id IS NULL OR v_booking.status IN ('CANCELLED', 'REJECTED', 'COMPLETED') THEN
    RAISE EXCEPTION 'BAD_REQUEST';
  END IF;

  SELECT * INTO v_venue
  FROM public.venues_resources
  WHERE id = p_venue_id AND is_active = true AND deleted_at IS NULL AND tenant_id = public.tenant_id();

  IF v_venue.id IS NULL THEN
    RAISE EXCEPTION 'BAD_REQUEST';
  END IF;

  SELECT * INTO v_priest
  FROM public.priests
  WHERE id = p_priest_id AND deleted_at IS NULL AND tenant_id = public.tenant_id();

  IF v_priest.id IS NULL THEN
    RAISE EXCEPTION 'BAD_REQUEST';
  END IF;

  -- Check if priest has conflicting schedule in priest_schedules
  IF EXISTS (
    SELECT 1 FROM public.priest_schedules
    WHERE priest_id = p_priest_id
      AND tenant_id = public.tenant_id()
      AND (booking_id IS NULL OR booking_id <> p_booking_id)
      AND schedule_range && v_booking.booking_range
  ) THEN
    RAISE EXCEPTION 'PRIEST_ALREADY_ASSIGNED' USING errcode = 'P0001';
  END IF;

  -- Check if venue is conflicting in event_bookings
  IF EXISTS (
    SELECT 1 FROM public.event_bookings
    WHERE id <> p_booking_id
      AND assigned_venue_id = p_venue_id
      AND status IN ('SUBMITTED', 'CONFIRMED', 'PENDING_PAYMENT', 'PAID')
      AND deleted_at IS NULL
      AND tenant_id = public.tenant_id()
      AND booking_range && v_booking.booking_range
  ) THEN
    RAISE EXCEPTION 'VENUE_ALREADY_BOOKED' USING errcode = 'P0001';
  END IF;

  -- Check if priest is conflicting in event_bookings
  IF EXISTS (
    SELECT 1 FROM public.event_bookings
    WHERE id <> p_booking_id
      AND assigned_priest_id = p_priest_id
      AND status IN ('SUBMITTED', 'CONFIRMED', 'PENDING_PAYMENT', 'PAID')
      AND deleted_at IS NULL
      AND tenant_id = public.tenant_id()
      AND booking_range && v_booking.booking_range
  ) THEN
    RAISE EXCEPTION 'PRIEST_ALREADY_ASSIGNED' USING errcode = 'P0001';
  END IF;

  -- Update event_bookings
  BEGIN
    UPDATE public.event_bookings
    SET assigned_venue_id = p_venue_id,
        assigned_priest_id = p_priest_id,
        status = 'CONFIRMED',
        notes = CASE
          WHEN p_override_notes IS NOT NULL AND length(trim(p_override_notes)) > 0
          THEN coalesce(notes || E'\n', '') || '[Admin Note]: ' || trim(p_override_notes)
          ELSE notes
        END,
        updated_at = now()
    WHERE id = p_booking_id
    RETURNING * INTO v_booking;
  EXCEPTION
    WHEN exclusion_violation THEN
      IF EXISTS (
        SELECT 1 FROM public.event_bookings
        WHERE id <> p_booking_id
          AND assigned_venue_id = p_venue_id
          AND status IN ('SUBMITTED', 'CONFIRMED', 'PENDING_PAYMENT', 'PAID')
          AND deleted_at IS NULL
          AND booking_range && v_booking.booking_range
      ) THEN
        RAISE EXCEPTION 'VENUE_ALREADY_BOOKED' USING errcode = 'P0001';
      ELSE
        RAISE EXCEPTION 'PRIEST_ALREADY_ASSIGNED' USING errcode = 'P0001';
      END IF;
  END;

  -- Upsert into priest_schedules
  IF EXISTS (SELECT 1 FROM public.priest_schedules WHERE booking_id = p_booking_id) THEN
    UPDATE public.priest_schedules
    SET priest_id = p_priest_id,
        schedule_range = v_booking.booking_range,
        schedule_type = 'EVENT_BOOKING',
        notes = 'حجز مناسبة: ' || v_booking.id::text,
        tenant_id = public.tenant_id()
    WHERE booking_id = p_booking_id;
  ELSE
    INSERT INTO public.priest_schedules (
      priest_id,
      schedule_range,
      schedule_type,
      booking_id,
      notes,
      tenant_id
    ) VALUES (
      p_priest_id,
      v_booking.booking_range,
      'EVENT_BOOKING',
      p_booking_id,
      'حجز مناسبة: ' || v_booking.id::text,
      public.tenant_id()
    );
  END IF;

  -- Audit log
  INSERT INTO public.audit_log (user_id, action, entity_type, entity_id, meta)
  VALUES (
    v_user,
    'admin_assign_priest_and_venue',
    'event_bookings',
    0,
    jsonb_build_object(
      'booking_id', p_booking_id,
      'assigned_venue_id', p_venue_id,
      'assigned_priest_id', p_priest_id,
      'start_time', v_booking.start_time,
      'end_time', v_booking.end_time
    )
  );

  -- WhatsApp Notification Outbox
  SELECT phone INTO v_customer_phone FROM public.users WHERE id = v_booking.customer_id;
  IF v_customer_phone IS NOT NULL THEN
    INSERT INTO public.event_outbox (handler_type, payload, tenant_id)
    VALUES (
      'WHATSAPP',
      jsonb_build_object(
        'phone', v_customer_phone,
        'template_name', 'event_booking_confirmed',
        'params', jsonb_build_object(
          'booking_id', v_booking.id,
          'venue_name', v_venue.name_ar,
          'priest_name', v_priest.name,
          'start_time', v_booking.start_time,
          'total_price_piastres', v_booking.total_price_piastres
        )
      ),
      public.tenant_id()
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'booking_id', p_booking_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_assign_priest_and_venue(UUID, UUID, BIGINT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_assign_priest_and_venue(UUID, UUID, BIGINT, TEXT) TO authenticated, service_role;

-- 9. Stored Procedure: get_available_priests
CREATE OR REPLACE FUNCTION public.get_available_priests(
  p_start_time TIMESTAMPTZ,
  p_end_time TIMESTAMPTZ
)
RETURNS TABLE (
  id BIGINT,
  name TEXT,
  photo_url TEXT,
  phone TEXT,
  rank TEXT,
  active_bookings_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_start_time IS NULL OR p_end_time IS NULL OR p_end_time <= p_start_time THEN
    RAISE EXCEPTION 'BAD_REQUEST' USING errcode = 'P0001';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.name,
    p.photo_url,
    COALESCE(p.phone, '') AS phone,
    COALESCE(p.rank, 'PRIEST') AS rank,
    COUNT(eb_count.id)::BIGINT AS active_bookings_count
  FROM public.priests p
  LEFT JOIN public.event_bookings eb_count
    ON eb_count.assigned_priest_id = p.id
   AND eb_count.deleted_at IS NULL
   AND eb_count.tenant_id = public.tenant_id()
   AND eb_count.status IN ('SUBMITTED', 'CONFIRMED', 'PENDING_PAYMENT', 'PAID')
  WHERE p.deleted_at IS NULL
    AND p.tenant_id = public.tenant_id()
    -- Not conflicting in priest_schedules
    AND NOT EXISTS (
      SELECT 1 FROM public.priest_schedules ps
      WHERE ps.priest_id = p.id
        AND ps.tenant_id = public.tenant_id()
        AND ps.schedule_range && tstzrange(p_start_time, p_end_time)
    )
    -- Not conflicting in active event_bookings
    AND NOT EXISTS (
      SELECT 1 FROM public.event_bookings eb
      WHERE eb.assigned_priest_id = p.id
        AND eb.deleted_at IS NULL
        AND eb.tenant_id = public.tenant_id()
        AND eb.status IN ('SUBMITTED', 'CONFIRMED', 'PENDING_PAYMENT', 'PAID')
        AND eb.booking_range && tstzrange(p_start_time, p_end_time)
    )
  GROUP BY p.id, p.name, p.photo_url, p.phone, p.rank
  ORDER BY p.name ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_available_priests(TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_available_priests(TIMESTAMPTZ, TIMESTAMPTZ) TO anon, authenticated, service_role;
