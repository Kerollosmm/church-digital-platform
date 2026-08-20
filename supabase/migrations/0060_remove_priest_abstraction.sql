-- 0060_remove_priest_abstraction.sql
-- Remove priest abstraction and drop is_admin_or_priest()

-- 1. Recreate 8 policies to use public.is_admin() (Hazard B)

-- faq
DROP POLICY IF EXISTS "faq admin write" ON public.faq;
CREATE POLICY "faq admin write" ON public.faq
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

-- services
DROP POLICY IF EXISTS "services admin write" ON public.services;
CREATE POLICY "services admin write" ON public.services
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

-- priests
DROP POLICY IF EXISTS "priests admin write" ON public.priests;
CREATE POLICY "priests admin write" ON public.priests
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

-- announcements
DROP POLICY IF EXISTS "announcements admin write" ON public.announcements;
CREATE POLICY "announcements admin write" ON public.announcements
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

-- service_slots
DROP POLICY IF EXISTS "service_slots admin write" ON public.service_slots;
CREATE POLICY "service_slots admin write" ON public.service_slots
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

-- slot_utilization_monthly
DROP POLICY IF EXISTS "p_analytics_read_admin" ON public.slot_utilization_monthly;
CREATE POLICY "p_analytics_read_admin" ON public.slot_utilization_monthly
  FOR SELECT TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id());

-- payments_monthly
DROP POLICY IF EXISTS "p_analytics_read_admin" ON public.payments_monthly;
CREATE POLICY "p_analytics_read_admin" ON public.payments_monthly
  FOR SELECT TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id());

-- bookings_monthly
DROP POLICY IF EXISTS "p_analytics_read_admin" ON public.bookings_monthly;
CREATE POLICY "p_analytics_read_admin" ON public.bookings_monthly
  FOR SELECT TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id());

-- 2. Update publish_announcement to use public.is_admin()
CREATE OR REPLACE FUNCTION public.publish_announcement(p_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ann public.announcements;
  v_has_images boolean := false;
  v_linked_count int := 0;
  v_invalid_count int := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_ann FROM public.announcements WHERE id = p_id;
  IF v_ann IS NULL THEN
    RAISE EXCEPTION 'ANNOUNCEMENT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  -- Check if announcement body or storage contains images
  IF v_ann.body_ar LIKE '%announcement_images%'
     OR EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id = 'announcement_images' AND (name LIKE 'ann' || p_id || '/%' OR name LIKE p_id || '/%'))
  THEN
    v_has_images := true;
  END IF;

  SELECT count(*) INTO v_linked_count
  FROM public.media_assets
  WHERE content_type = 'announcement' AND content_id = p_id;

  IF v_has_images AND v_linked_count = 0 THEN
    RAISE EXCEPTION 'ALT_TEXT_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  SELECT count(*) INTO v_invalid_count
  FROM public.media_assets
  WHERE content_type = 'announcement' AND content_id = p_id
    AND is_decorative = false
    AND (alt_text_ar IS NULL OR length(trim(alt_text_ar)) = 0);

  IF v_invalid_count > 0 THEN
    RAISE EXCEPTION 'ALT_TEXT_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.announcements
  SET published_at = now(),
      updated_at = now()
  WHERE id = p_id;
END;
$$;

-- 3. Drop is_admin_or_priest function
DROP FUNCTION IF EXISTS public.is_admin_or_priest();
