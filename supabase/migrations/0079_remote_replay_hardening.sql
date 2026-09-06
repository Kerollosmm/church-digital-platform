-- ==============================================================================
-- 0079_remote_replay_hardening.sql
-- Forward hardening migration:
-- 1. Server-side cashier search query RPC (search_cashier_bookings)
-- 2. Indexes for cashier search and customer bookings lookup
-- 3. Privilege hardening for cashier queries
-- ==============================================================================

-- 1. Indexes on event_bookings for customer lookup and cashier searches
CREATE INDEX IF NOT EXISTS idx_event_bookings_tenant_created 
  ON public.event_bookings (tenant_id, created_at DESC) 
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_event_bookings_customer_search 
  ON public.event_bookings (customer_id, status) 
  WHERE deleted_at IS NULL;

-- 2. Stored Procedure: search_cashier_bookings
CREATE OR REPLACE FUNCTION public.search_cashier_bookings(
  p_search_query TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  event_type_id UUID,
  event_type_name TEXT,
  category TEXT,
  customer_id UUID,
  customer_name TEXT,
  customer_phone TEXT,
  start_time TIMESTAMPTZ,
  end_time TIMESTAMPTZ,
  status TEXT,
  total_price_piastres BIGINT,
  paid_amount_piastres BIGINT,
  remaining_amount_piastres BIGINT,
  assigned_venue_id UUID,
  venue_name TEXT,
  assigned_priest_id BIGINT,
  priest_name TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_q TEXT;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING errcode = '28000';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;

  v_q := trim(COALESCE(p_search_query, ''));

  RETURN QUERY
  SELECT
    eb.id,
    eb.event_type_id,
    et.name_ar AS event_type_name,
    et.category,
    eb.customer_id,
    COALESCE(u.name, '') AS customer_name,
    COALESCE(u.phone, '') AS customer_phone,
    eb.start_time,
    eb.end_time,
    eb.status::TEXT,
    eb.total_price_piastres,
    eb.paid_amount_piastres,
    GREATEST(0::BIGINT, eb.total_price_piastres - eb.paid_amount_piastres) AS remaining_amount_piastres,
    eb.assigned_venue_id,
    COALESCE(vr.name_ar, '') AS venue_name,
    eb.assigned_priest_id,
    COALESCE(p.name, '') AS priest_name,
    eb.created_at
  FROM public.event_bookings eb
  JOIN public.event_types et ON et.id = eb.event_type_id AND et.tenant_id = public.tenant_id()
  LEFT JOIN public.users u ON u.id = eb.customer_id
  LEFT JOIN public.venues_resources vr ON vr.id = eb.assigned_venue_id AND vr.tenant_id = public.tenant_id()
  LEFT JOIN public.priests p ON p.id = eb.assigned_priest_id AND p.tenant_id = public.tenant_id()
  WHERE eb.tenant_id = public.tenant_id()
    AND eb.deleted_at IS NULL
    AND (p_category IS NULL OR et.category = p_category)
    AND (
      v_q = ''
      OR u.phone ILIKE '%' || v_q || '%'
      OR u.name ILIKE '%' || v_q || '%'
      OR et.name_ar ILIKE '%' || v_q || '%'
      OR eb.id::TEXT ILIKE '%' || v_q || '%'
    )
  ORDER BY eb.created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 200))
  OFFSET GREATEST(0, p_offset);
END;
$$;

-- 3. Privilege hardening
REVOKE ALL ON FUNCTION public.search_cashier_bookings(TEXT, TEXT, INT, INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.search_cashier_bookings(TEXT, TEXT, INT, INT) TO authenticated, service_role;
