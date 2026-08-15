-- supabase/migrations/0023_analytics_views.sql
-- security_invoker: views run with the CALLER's rights, so RLS on the base tables applies
CREATE OR REPLACE VIEW public.v_analytics_utilization WITH (security_invoker = true) AS
SELECT s.title_ar, u.month, u.slots_total, u.slots_booked, u.utilization_pct
FROM public.slot_utilization_monthly u
JOIN public.services s ON s.id = u.service_id;

CREATE OR REPLACE VIEW public.v_analytics_payments WITH (security_invoker = true) AS
SELECT p.month, p.total_paid, p.total_refunded, p.count_paid
FROM public.payments_monthly p;

CREATE OR REPLACE VIEW public.v_analytics_bookings WITH (security_invoker = true) AS
SELECT s.title_ar, b.month, b.bookings_total, b.by_status
FROM public.bookings_monthly b
JOIN public.services s ON s.id = b.service_id;

ALTER TABLE public.slot_utilization_monthly ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments_monthly ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings_monthly ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_analytics_read_admin ON public.slot_utilization_monthly;
CREATE POLICY p_analytics_read_admin ON public.slot_utilization_monthly
  FOR SELECT USING (public.is_admin_or_priest());

DROP POLICY IF EXISTS p_analytics_read_admin ON public.payments_monthly;
CREATE POLICY p_analytics_read_admin ON public.payments_monthly
  FOR SELECT USING (public.is_admin_or_priest());

DROP POLICY IF EXISTS p_analytics_read_admin ON public.bookings_monthly;
CREATE POLICY p_analytics_read_admin ON public.bookings_monthly
  FOR SELECT USING (public.is_admin_or_priest());
