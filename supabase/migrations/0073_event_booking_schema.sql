-- ==============================================================================
-- 0073_event_booking_schema.sql
-- Spec 008: Event Booking with Extra Services
-- Domain entities, GiST temporal exclusion constraints for venues, price snapshotting,
-- immutable payment audit ledger, RLS policies, and outbox template checks.
-- ==============================================================================

-- 1. Extension
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 2. Types & Enums
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_booking_status') THEN
    CREATE TYPE public.event_booking_status AS ENUM (
      'SUBMITTED',
      'AWAITING_CALL',
      'CONFIRMED',
      'PAID',
      'COMPLETED',
      'REJECTED',
      'CANCELLED'
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_audit_action') THEN
    CREATE TYPE public.payment_audit_action AS ENUM (
      'CASH_COLLECTED',
      'PROOF_APPROVED',
      'ADJUSTMENT',
      'REFUND'
    );
  END IF;
END $$;

-- 3. Catalog Tables
CREATE TABLE IF NOT EXISTS public.event_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name_ar TEXT NOT NULL,
  description_ar TEXT,
  base_price_piastres BIGINT NOT NULL CHECK (base_price_piastres >= 0),
  default_duration_minutes INT NOT NULL CHECK (default_duration_minutes > 0),
  is_active BOOLEAN NOT NULL DEFAULT true,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.extra_services (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name_ar TEXT NOT NULL,
  description_ar TEXT,
  price_piastres BIGINT NOT NULL CHECK (price_piastres >= 0),
  is_quantity_based BOOLEAN NOT NULL DEFAULT false,
  max_quantity INT NOT NULL DEFAULT 1 CHECK (max_quantity >= 1),
  is_active BOOLEAN NOT NULL DEFAULT true,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.event_type_extra_services (
  event_type_id UUID NOT NULL REFERENCES public.event_types(id) ON DELETE CASCADE,
  extra_service_id UUID NOT NULL REFERENCES public.extra_services(id) ON DELETE CASCADE,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  PRIMARY KEY (event_type_id, extra_service_id)
);

CREATE TABLE IF NOT EXISTS public.venues_resources (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name_ar TEXT NOT NULL,
  location_details_ar TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

-- 4. Event Bookings & Line Items
CREATE TABLE IF NOT EXISTS public.event_bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES public.users(id),
  event_type_id UUID NOT NULL REFERENCES public.event_types(id),
  assigned_venue_id UUID REFERENCES public.venues_resources(id),
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ NOT NULL,
  booking_range TSTZRANGE GENERATED ALWAYS AS (tstzrange(start_time, end_time)) STORED,
  status public.event_booking_status NOT NULL DEFAULT 'SUBMITTED',
  notes TEXT,
  rejection_reason TEXT,
  base_price_piastres BIGINT NOT NULL DEFAULT 0 CHECK (base_price_piastres >= 0),
  extra_services_price_piastres BIGINT NOT NULL DEFAULT 0 CHECK (extra_services_price_piastres >= 0),
  total_price_piastres BIGINT NOT NULL DEFAULT 0 CHECK (total_price_piastres >= 0),
  paid_amount_piastres BIGINT NOT NULL DEFAULT 0 CHECK (paid_amount_piastres >= 0),
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ,
  CONSTRAINT valid_booking_time_range CHECK (end_time > start_time)
);

-- Range Exclusion Constraint for Venues (prevents overlapping confirmed/paid bookings)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'no_overlapping_venue_events'
  ) THEN
    ALTER TABLE public.event_bookings
    ADD CONSTRAINT no_overlapping_venue_events
    EXCLUDE USING gist (
      assigned_venue_id WITH =,
      booking_range WITH &&
    )
    WHERE (status NOT IN ('CANCELLED', 'REJECTED', 'SUBMITTED') AND deleted_at IS NULL AND assigned_venue_id IS NOT NULL);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.booking_extra_services (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_id UUID NOT NULL REFERENCES public.event_bookings(id) ON DELETE CASCADE,
  extra_service_id UUID NOT NULL REFERENCES public.extra_services(id),
  unit_price_piastres BIGINT NOT NULL CHECK (unit_price_piastres >= 0),
  quantity INT NOT NULL DEFAULT 1 CHECK (quantity >= 1),
  total_price_piastres BIGINT NOT NULL CHECK (total_price_piastres >= 0),
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. Payment Audit Log (Immutable ledger)
CREATE TABLE IF NOT EXISTS public.payment_audit_logs (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_id UUID NOT NULL REFERENCES public.event_bookings(id) ON DELETE CASCADE,
  amount_piastres BIGINT NOT NULL CHECK (amount_piastres > 0),
  method TEXT NOT NULL,
  recorded_by UUID NOT NULL REFERENCES public.users(id),
  action public.payment_audit_action NOT NULL,
  notes TEXT,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 6. Indexes
CREATE INDEX IF NOT EXISTS idx_event_bookings_customer ON public.event_bookings(customer_id);
CREATE INDEX IF NOT EXISTS idx_event_bookings_status ON public.event_bookings(status);
CREATE INDEX IF NOT EXISTS idx_event_bookings_tenant ON public.event_bookings(tenant_id);
CREATE INDEX IF NOT EXISTS idx_booking_extra_services_booking ON public.booking_extra_services(booking_id);
CREATE INDEX IF NOT EXISTS idx_payment_audit_logs_booking ON public.payment_audit_logs(booking_id);

-- 7. Enable RLS (Mandatory 2 statements per AGENTS.md)
ALTER TABLE public.event_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.extra_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_type_extra_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.venues_resources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.booking_extra_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_audit_logs ENABLE ROW LEVEL SECURITY;

-- 8. Policies
-- Catalog: Active rows readable by authenticated and anon, full write for admins
DROP POLICY IF EXISTS "Public read active event_types" ON public.event_types;
CREATE POLICY "Public read active event_types" ON public.event_types
  FOR SELECT TO anon, authenticated
  USING (is_active = true AND deleted_at IS NULL AND tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Admin manage event_types" ON public.event_types;
CREATE POLICY "Admin manage event_types" ON public.event_types
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Public read active extra_services" ON public.extra_services;
CREATE POLICY "Public read active extra_services" ON public.extra_services
  FOR SELECT TO anon, authenticated
  USING (is_active = true AND deleted_at IS NULL AND tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Admin manage extra_services" ON public.extra_services;
CREATE POLICY "Admin manage extra_services" ON public.extra_services
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Public read event_type_extra_services" ON public.event_type_extra_services;
CREATE POLICY "Public read event_type_extra_services" ON public.event_type_extra_services
  FOR SELECT TO anon, authenticated
  USING (tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Admin manage event_type_extra_services" ON public.event_type_extra_services;
CREATE POLICY "Admin manage event_type_extra_services" ON public.event_type_extra_services
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Public read active venues" ON public.venues_resources;
CREATE POLICY "Public read active venues" ON public.venues_resources
  FOR SELECT TO anon, authenticated
  USING (is_active = true AND deleted_at IS NULL AND tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Admin manage venues" ON public.venues_resources;
CREATE POLICY "Admin manage venues" ON public.venues_resources
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

-- Bookings & Line items: Members read own, Admins read all
DROP POLICY IF EXISTS "Members read own event_bookings" ON public.event_bookings;
CREATE POLICY "Members read own event_bookings" ON public.event_bookings
  FOR SELECT TO authenticated
  USING (customer_id = auth.uid() AND tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Admins read all event_bookings" ON public.event_bookings;
CREATE POLICY "Admins read all event_bookings" ON public.event_bookings
  FOR SELECT TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id());

-- Helper function for booking extra services ownership
CREATE OR REPLACE FUNCTION public.is_event_booking_owner(p_booking_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.event_bookings
    WHERE id = p_booking_id AND customer_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.is_event_booking_owner(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_event_booking_owner(UUID) TO authenticated, service_role;

DROP POLICY IF EXISTS "Members read own booking extra services" ON public.booking_extra_services;
CREATE POLICY "Members read own booking extra services" ON public.booking_extra_services
  FOR SELECT TO authenticated
  USING (
    tenant_id = public.tenant_id()
    AND public.is_event_booking_owner(booking_id)
  );

DROP POLICY IF EXISTS "Admins read all booking extra services" ON public.booking_extra_services;
CREATE POLICY "Admins read all booking extra services" ON public.booking_extra_services
  FOR SELECT TO authenticated
  USING (
    tenant_id = public.tenant_id()
    AND public.is_admin()
  );

-- Payment Audit Logs: Admins only
DROP POLICY IF EXISTS "Admins read payment audit logs" ON public.payment_audit_logs;
CREATE POLICY "Admins read payment audit logs" ON public.payment_audit_logs
  FOR SELECT TO authenticated
  USING (
    tenant_id = public.tenant_id()
    AND public.is_admin()
  );

-- 9. Explicit Permissions (Revoke client DML on sensitive tables)
REVOKE INSERT, UPDATE, DELETE ON public.event_bookings FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.booking_extra_services FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.payment_audit_logs FROM anon, authenticated;

GRANT SELECT ON public.event_types, public.extra_services, public.event_type_extra_services, public.venues_resources TO anon, authenticated;
GRANT SELECT ON public.event_bookings, public.booking_extra_services, public.payment_audit_logs TO anon, authenticated;

-- Service role full access
GRANT SELECT, INSERT, UPDATE, DELETE ON public.event_types, public.extra_services, public.event_type_extra_services, public.venues_resources, public.event_bookings, public.booking_extra_services, public.payment_audit_logs TO service_role;

-- 10. Update event_outbox template constraint to support Spec 008 WhatsApp templates
ALTER TABLE public.event_outbox
  DROP CONSTRAINT IF EXISTS event_outbox_whatsapp_template_check;

ALTER TABLE public.event_outbox
  ADD CONSTRAINT event_outbox_whatsapp_template_check
  CHECK (
    handler_type <> 'WHATSAPP'
    OR (payload->>'template_name') IN (
      'booking_confirmed',
      'payment_received',
      'booking_cancelled',
      'booking_rescheduled',
      'booking_apology',
      'otp_auth',
      'booking_payment_received',
      'booking_offer',
      'admin_security_alert',
      'event_booking_submitted',
      'event_booking_confirmed',
      'event_booking_rejected',
      'event_booking_payment_received'
    )
  );
