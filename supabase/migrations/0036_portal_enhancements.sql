-- 0036_portal_enhancements.sql
-- 1. Ensure Realtime Publication includes bookings and service_slots
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr
    JOIN pg_publication p ON p.oid = pr.prpubid
    JOIN pg_class c ON c.oid = pr.prrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE p.pubname = 'supabase_realtime' AND n.nspname = 'public' AND c.relname = 'bookings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.bookings;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr
    JOIN pg_publication p ON p.oid = pr.prpubid
    JOIN pg_class c ON c.oid = pr.prrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE p.pubname = 'supabase_realtime' AND n.nspname = 'public' AND c.relname = 'service_slots'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.service_slots;
  END IF;
END $$;

-- 2. Create v_my_bookings view with full service details
DROP VIEW IF EXISTS public.v_my_bookings;
CREATE VIEW public.v_my_bookings WITH (security_invoker = true) AS
SELECT b.id, b.slot_id, b.user_id, b.status, b.paid_amount, b.created_at, b.locked_until,
       s.title_ar AS service_name, sl.starts_at, sl.ends_at, sl.location
FROM public.bookings b
JOIN public.service_slots sl ON sl.id = b.slot_id
JOIN public.services s ON s.id = sl.service_id
WHERE b.user_id = auth.uid() AND b.tenant_id = public.tenant_id();
