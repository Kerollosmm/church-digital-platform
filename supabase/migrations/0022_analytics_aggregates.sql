-- supabase/migrations/0022_analytics_aggregates.sql
CREATE TABLE IF NOT EXISTS public.slot_utilization_monthly (
  service_id bigint REFERENCES public.services(id) ON DELETE CASCADE,
  month date NOT NULL,
  slots_total int NOT NULL DEFAULT 0,
  slots_booked int NOT NULL DEFAULT 0,
  utilization_pct numeric(5,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (service_id, month)
);

CREATE TABLE IF NOT EXISTS public.payments_monthly (
  month date NOT NULL,
  total_paid numeric(12,2) NOT NULL DEFAULT 0,
  total_refunded numeric(12,2) NOT NULL DEFAULT 0,
  count_paid int NOT NULL DEFAULT 0,
  PRIMARY KEY (month)
);

CREATE TABLE IF NOT EXISTS public.bookings_monthly (
  service_id bigint REFERENCES public.services(id) ON DELETE CASCADE,
  month date NOT NULL,
  bookings_total int NOT NULL DEFAULT 0,
  by_status jsonb NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (service_id, month)
);

CREATE OR REPLACE FUNCTION public.materialize_analytics()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE m date := (date_trunc('month', now() AT TIME ZONE 'Africa/Cairo'))::date;
BEGIN
  DELETE FROM public.slot_utilization_monthly WHERE month = m;
  INSERT INTO public.slot_utilization_monthly (service_id, month, slots_total, slots_booked, utilization_pct)
  SELECT
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
  GROUP BY s.id;

  DELETE FROM public.payments_monthly WHERE month = m;
  INSERT INTO public.payments_monthly (month, total_paid, total_refunded, count_paid)
  SELECT m,
    COALESCE(sum(amount) FILTER (WHERE status = 'PAID'), 0),
    COALESCE(sum(amount) FILTER (WHERE status = 'REFUNDED'), 0),
    count(*) FILTER (WHERE status = 'PAID')
  FROM public.payments WHERE created_at AT TIME ZONE 'Africa/Cairo' >= m;

  DELETE FROM public.bookings_monthly WHERE month = m;
  WITH agg AS (
    SELECT sl.service_id, b.status, count(*) AS cnt
    FROM public.bookings b
    JOIN public.service_slots sl ON sl.id = b.slot_id
    WHERE b.created_at AT TIME ZONE 'Africa/Cairo' >= m
      AND b.created_at AT TIME ZONE 'Africa/Cairo' < m + interval '1 month'
    GROUP BY sl.service_id, b.status
  ),
  by_svc AS (
    SELECT service_id, sum(cnt) AS total, jsonb_object_agg(status, cnt) AS status_map
    FROM agg GROUP BY service_id
  )
  INSERT INTO public.bookings_monthly (service_id, month, bookings_total, by_status)
  SELECT s.id, m, COALESCE(bs.total, 0), COALESCE(bs.status_map, '{}'::jsonb)
  FROM public.services s
  LEFT JOIN by_svc bs ON bs.service_id = s.id;
END $$;

ALTER TABLE public.slot_utilization_monthly ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments_monthly ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings_monthly ENABLE ROW LEVEL SECURITY;

SELECT cron.schedule('analytics-nightly', '0 2 * * *', $$SELECT public.materialize_analytics()$$);

