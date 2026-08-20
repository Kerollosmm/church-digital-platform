-- 0064_event_booking_schema.sql
-- Spec 008 Event Booking with Extra Services Database Schema & Exclusion Constraints

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 1. Extend booking_status enum with missing review and payment statuses
ALTER TYPE booking_status ADD VALUE IF NOT EXISTS 'SUBMITTED';
ALTER TYPE booking_status ADD VALUE IF NOT EXISTS 'REJECTED';
ALTER TYPE booking_status ADD VALUE IF NOT EXISTS 'PARTIALLY_PAID';

-- 2. Venues & Resources Table
CREATE TABLE IF NOT EXISTS public.venues_resources (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  name_ar TEXT NOT NULL,
  description_ar TEXT,
  capacity INT NOT NULL CHECK (capacity > 0),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.venues_resources ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow authenticated read active venues_resources" ON public.venues_resources;
CREATE POLICY "Allow authenticated read active venues_resources" ON public.venues_resources
  FOR SELECT TO authenticated USING (tenant_id = public.tenant_id() AND is_active = true);

DROP POLICY IF EXISTS "Allow admin full manage venues_resources" ON public.venues_resources;
CREATE POLICY "Allow admin full manage venues_resources" ON public.venues_resources
  FOR ALL TO authenticated USING (public.is_admin() AND tenant_id = public.tenant_id());

ALTER TABLE public.event_types ADD COLUMN IF NOT EXISTS name_ar TEXT;
ALTER TABLE public.event_types ADD COLUMN IF NOT EXISTS base_price_piastres BIGINT DEFAULT 0 CHECK (base_price_piastres >= 0);
ALTER TABLE public.event_types ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

ALTER TABLE public.extra_services ADD COLUMN IF NOT EXISTS name_ar TEXT;
ALTER TABLE public.extra_services ADD COLUMN IF NOT EXISTS unit_price_piastres BIGINT DEFAULT 0 CHECK (unit_price_piastres >= 0);
ALTER TABLE public.extra_services ADD COLUMN IF NOT EXISTS is_quantity_based BOOLEAN DEFAULT false;
ALTER TABLE public.extra_services ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

CREATE TABLE IF NOT EXISTS public.event_type_extra_services (
  event_type_id BIGINT NOT NULL REFERENCES public.event_types(id) ON DELETE CASCADE,
  extra_service_id BIGINT NOT NULL REFERENCES public.extra_services(id) ON DELETE CASCADE,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (event_type_id, extra_service_id)
);

ALTER TABLE public.event_type_extra_services ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow authenticated read event extra mappings" ON public.event_type_extra_services;
CREATE POLICY "Allow authenticated read event extra mappings" ON public.event_type_extra_services
  FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Allow admin manage event extra mappings" ON public.event_type_extra_services;
CREATE POLICY "Allow admin manage event extra mappings" ON public.event_type_extra_services
  FOR ALL TO authenticated USING (public.is_admin() AND tenant_id = public.tenant_id());

CREATE TABLE IF NOT EXISTS public.booking_extra_services (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  booking_id BIGINT NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  extra_service_id BIGINT NOT NULL REFERENCES public.extra_services(id),
  unit_price_snapshot_piastres BIGINT NOT NULL CHECK (unit_price_snapshot_piastres >= 0),
  quantity INT NOT NULL DEFAULT 1 CHECK (quantity >= 1),
  total_price_snapshot_piastres BIGINT NOT NULL CHECK (total_price_snapshot_piastres >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.booking_extra_services ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow user or admin view booking extras" ON public.booking_extra_services;
CREATE POLICY "Allow user or admin view booking extras" ON public.booking_extra_services
  FOR SELECT TO authenticated USING (
    tenant_id = public.tenant_id() AND (
      public.is_admin() OR EXISTS (
        SELECT 1 FROM public.bookings b WHERE b.id = booking_extra_services.booking_id AND b.user_id = auth.uid()
      )
    )
  );

CREATE TABLE IF NOT EXISTS public.event_resource_bookings (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  booking_id BIGINT NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  resource_id BIGINT NOT NULL REFERENCES public.venues_resources(id),
  booking_period TSTZRANGE NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'exclude_overlapping_resource_bookings'
  ) THEN
    ALTER TABLE public.event_resource_bookings ADD CONSTRAINT exclude_overlapping_resource_bookings EXCLUDE USING gist (
      resource_id WITH =,
      booking_period WITH &&
    ) WHERE (is_active = true);
  END IF;
END $$;

ALTER TABLE public.event_resource_bookings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow authenticated view resource bookings" ON public.event_resource_bookings;
CREATE POLICY "Allow authenticated view resource bookings" ON public.event_resource_bookings
  FOR SELECT TO authenticated USING (tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Allow admin manage resource bookings" ON public.event_resource_bookings;
CREATE POLICY "Allow admin manage resource bookings" ON public.event_resource_bookings
  FOR ALL TO authenticated USING (public.is_admin() AND tenant_id = public.tenant_id());

CREATE TABLE IF NOT EXISTS public.payment_audit_logs (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  booking_id BIGINT NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  recorded_by UUID NOT NULL REFERENCES public.users(id),
  payment_method TEXT NOT NULL CHECK (payment_method IN ('CASH', 'ONLINE', 'OVERRIDE')),
  amount_piastres BIGINT NOT NULL CHECK (amount_piastres > 0),
  receipt_reference TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.payment_audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow admin view payment audit logs" ON public.payment_audit_logs;
CREATE POLICY "Allow admin view payment audit logs" ON public.payment_audit_logs
  FOR SELECT TO authenticated USING (public.is_admin() AND tenant_id = public.tenant_id());

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;
