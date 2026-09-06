-- 0058_status_enums.sql
-- Create domain status enums and convert text columns

-- 1. Create enum types idempotently
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'slot_status') THEN
    CREATE TYPE public.slot_status AS ENUM ('OPEN', 'CLOSED');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'waitlist_status') THEN
    CREATE TYPE public.waitlist_status AS ENUM ('WAITING', 'OFFERED');
  END IF;
END $$;

-- 2. Drop dependent views and exclusion constraint before column type conversion (Hazard A)
DROP VIEW IF EXISTS public.v_available_slots;
DROP VIEW IF EXISTS public.v_schedule_today;
DROP VIEW IF EXISTS public.v_services;

ALTER TABLE public.service_slots
  DROP CONSTRAINT IF EXISTS no_location_schedule_overlap;

-- 3. Convert service_slots.status
ALTER TABLE public.service_slots ALTER COLUMN status DROP DEFAULT;
ALTER TABLE public.service_slots ALTER COLUMN status TYPE public.slot_status USING status::public.slot_status;
ALTER TABLE public.service_slots ALTER COLUMN status SET DEFAULT 'OPEN'::public.slot_status;

-- Re-add exclusion constraint with typed enum comparison
ALTER TABLE public.service_slots
  ADD CONSTRAINT no_location_schedule_overlap
  EXCLUDE USING GIST (
    location WITH =,
    schedule_range WITH &&
  ) WHERE (status <> 'CLOSED'::public.slot_status);

-- 4. Convert waiting_list.status
ALTER TABLE public.waiting_list ALTER COLUMN status DROP DEFAULT;
ALTER TABLE public.waiting_list ALTER COLUMN status TYPE public.waitlist_status USING status::public.waitlist_status;
ALTER TABLE public.waiting_list ALTER COLUMN status SET DEFAULT 'WAITING'::public.waitlist_status;

-- 5. Recreate views verbatim with security_invoker = true
CREATE VIEW public.v_services WITH (security_invoker = true) AS
SELECT s.id, s.title_ar, s.description, s.location,
       min(sl.starts_at) filter (where sl.status <> 'CLOSED' and sl.starts_at > now()) as next_slot_starts_at,
       min(sl.price) filter (where sl.status <> 'CLOSED' and sl.starts_at > now()) as price_from,
       s.tenant_id
FROM public.services s
LEFT JOIN public.service_slots sl ON sl.service_id = s.id
WHERE s.tenant_id = public.tenant_id()
GROUP BY s.id;

CREATE VIEW public.v_available_slots WITH (security_invoker = true) AS
SELECT s.id AS slot_id, s.service_id, sv.title_ar, s.starts_at, s.ends_at,
       s.capacity, s.price, s.location,
       public.active_booking_count(s.id) AS booked_count,
       greatest(s.capacity - public.active_booking_count(s.id), 0) AS available_seats,
       CASE
         WHEN s.status = 'CLOSED' THEN 'CLOSED'
         WHEN s.starts_at <= now() THEN 'CLOSED'
         WHEN public.active_booking_count(s.id) >= s.capacity THEN 'BOOKED'
         ELSE 'AVAILABLE'
       END AS slot_status
FROM public.service_slots s
JOIN public.services sv ON sv.id = s.service_id
WHERE s.tenant_id = public.tenant_id();

CREATE VIEW public.v_schedule_today WITH (security_invoker = true) AS
SELECT sl.id AS slot_id, s.title_ar, sl.starts_at, sl.ends_at, sl.location,
       CASE WHEN public.active_booking_count(sl.id) > 0 THEN 'BOOKED' ELSE 'AVAILABLE' END AS display_status
FROM public.service_slots sl
JOIN public.services s ON s.id = sl.service_id
WHERE sl.starts_at >= date_trunc('day', now())
  AND sl.starts_at <  date_trunc('day', now()) + interval '1 day'
  AND sl.status <> 'CLOSED'
  AND sl.tenant_id = public.tenant_id()
ORDER BY sl.starts_at;

-- 6. Restore grants (Hazard A)
GRANT SELECT ON public.v_services TO anon, authenticated;
GRANT SELECT ON public.v_available_slots TO anon, authenticated;
GRANT SELECT ON public.v_schedule_today TO anon, authenticated;
