-- ==============================================================================
-- 0049_accessibility_foundations.sql
-- Feature: 004-accessibility-foundations (Phase 2 & Phase 3 foundations)
-- Purpose: media_assets registry, error_messages catalog, publish gates, delivery RPC
-- ==============================================================================

-- ==============================================================================
-- 1. Table: public.media_assets
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.media_assets (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  bucket TEXT NOT NULL CHECK (bucket IN ('priest_photos', 'church_media', 'announcement_images')),
  storage_path TEXT NOT NULL,
  alt_text_ar TEXT,
  is_decorative BOOLEAN NOT NULL DEFAULT false,
  content_type TEXT NULL CHECK (content_type IS NULL OR content_type IN ('announcement', 'priest', 'media')),
  content_id BIGINT NULL,
  language TEXT NOT NULL DEFAULT 'ar',
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  CONSTRAINT uq_media_assets_path UNIQUE (bucket, storage_path, tenant_id),
  CONSTRAINT chk_media_assets_alt_text CHECK (
    (is_decorative = true AND alt_text_ar IS NULL) OR
    (alt_text_ar IS NOT NULL AND length(trim(alt_text_ar)) > 0)
  )
);

-- ==============================================================================
-- 2. Table: public.error_messages
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.error_messages (
  code TEXT PRIMARY KEY CHECK (code IN ('UNAUTHORIZED', 'FORBIDDEN', 'BAD_REQUEST', 'UPSTREAM_ERROR', 'INTERNAL', 'FALLBACK')),
  message_ar TEXT NOT NULL CHECK (length(trim(message_ar)) > 0),
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id()
);

-- ==============================================================================
-- 3. Enable RLS
-- ==============================================================================
ALTER TABLE public.media_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.error_messages ENABLE ROW LEVEL SECURITY;

-- ==============================================================================
-- 4. Policies: media_assets
-- ==============================================================================
DROP POLICY IF EXISTS "Anyone can read media assets in tenant" ON public.media_assets;
CREATE POLICY "Anyone can read media assets in tenant"
  ON public.media_assets
  FOR SELECT
  TO anon, authenticated
  USING (tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Admins can insert media assets" ON public.media_assets;
CREATE POLICY "Admins can insert media assets"
  ON public.media_assets
  FOR INSERT
  TO authenticated
  WITH CHECK (
    tenant_id = public.tenant_id()
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Admins can update media assets" ON public.media_assets;
CREATE POLICY "Admins can update media assets"
  ON public.media_assets
  FOR UPDATE
  TO authenticated
  USING (
    tenant_id = public.tenant_id()
    AND public.is_admin()
  )
  WITH CHECK (
    tenant_id = public.tenant_id()
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Admins can delete media assets" ON public.media_assets;
CREATE POLICY "Admins can delete media assets"
  ON public.media_assets
  FOR DELETE
  TO authenticated
  USING (
    tenant_id = public.tenant_id()
    AND public.is_admin()
  );

-- ==============================================================================
-- 5. Policies: error_messages
-- ==============================================================================
DROP POLICY IF EXISTS "Anyone can read error messages in tenant" ON public.error_messages;
CREATE POLICY "Anyone can read error messages in tenant"
  ON public.error_messages
  FOR SELECT
  TO anon, authenticated
  USING (tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "Admins can insert error messages" ON public.error_messages;
CREATE POLICY "Admins can insert error messages"
  ON public.error_messages
  FOR INSERT
  TO authenticated
  WITH CHECK (
    tenant_id = public.tenant_id()
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Admins can update error messages" ON public.error_messages;
CREATE POLICY "Admins can update error messages"
  ON public.error_messages
  FOR UPDATE
  TO authenticated
  USING (
    tenant_id = public.tenant_id()
    AND public.is_admin()
  )
  WITH CHECK (
    tenant_id = public.tenant_id()
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Admins can delete error messages" ON public.error_messages;
CREATE POLICY "Admins can delete error messages"
  ON public.error_messages
  FOR DELETE
  TO authenticated
  USING (
    tenant_id = public.tenant_id()
    AND public.is_admin()
  );

-- ==============================================================================
-- 6. Permissions & Sequence Grants
-- ==============================================================================
GRANT SELECT ON public.media_assets TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.media_assets TO authenticated;

GRANT SELECT ON public.error_messages TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.error_messages TO authenticated;

GRANT USAGE, SELECT ON SEQUENCE public.media_assets_id_seq TO authenticated;

-- ==============================================================================
-- 7. Seed Data: error_messages
-- ==============================================================================
INSERT INTO public.error_messages (code, message_ar)
VALUES
  ('UNAUTHORIZED', 'انتهت الجلسة، من فضلك سجل الدخول مرة أخرى.'),
  ('FORBIDDEN', 'ليس لديك صلاحية للوصول إلى هذه الخدمة.'),
  ('BAD_REQUEST', 'البيانات المرسلة غير صحيحة، يرجى التأكد والمحاولة مرة أخرى.'),
  ('UPSTREAM_ERROR', 'تعذر الاتصال بالخدمة الخارجية، يرجى المحاولة لاحقاً.'),
  ('INTERNAL', 'حدث خطأ في النظام، يرجى المحاولة لاحقاً.'),
  ('FALLBACK', 'حدث خطأ غير متوقع، حاول مرة أخرى.')
ON CONFLICT (code) DO UPDATE
SET message_ar = EXCLUDED.message_ar;

-- ==============================================================================
-- 8. Alter announcements to allow draft status (published_at NULL)
-- ==============================================================================
ALTER TABLE public.announcements ALTER COLUMN published_at DROP NOT NULL;

-- ==============================================================================
-- 9. RPC: publish_announcement
-- ==============================================================================
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
  IF NOT public.is_admin_or_priest() THEN
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

REVOKE ALL ON FUNCTION public.publish_announcement(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_announcement(bigint) TO authenticated;

-- ==============================================================================
-- 10. RPC: set_priest_photo
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.set_priest_photo(
  p_priest_id bigint,
  p_media_asset_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_asset public.media_assets;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.priests WHERE id = p_priest_id) THEN
    RAISE EXCEPTION 'PRIEST_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_asset FROM public.media_assets WHERE id = p_media_asset_id;
  IF v_asset IS NULL OR v_asset.bucket <> 'priest_photos'
     OR (NOT v_asset.is_decorative AND (v_asset.alt_text_ar IS NULL OR length(trim(v_asset.alt_text_ar)) = 0))
  THEN
    RAISE EXCEPTION 'INVALID_MEDIA_ASSET' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.priests
  SET photo_url = v_asset.storage_path,
      updated_at = now()
  WHERE id = p_priest_id;

  UPDATE public.media_assets
  SET content_type = 'priest',
      content_id = p_priest_id
  WHERE id = p_media_asset_id;
END;
$$;

REVOKE ALL ON FUNCTION public.set_priest_photo(bigint, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_priest_photo(bigint, bigint) TO authenticated;

-- ==============================================================================
-- 11. View: v_content_backlog
-- ==============================================================================
CREATE OR REPLACE VIEW public.v_content_backlog AS
SELECT
  'missing_alt_text'::text AS kind,
  p.created_at AS source_created_at,
  p.id AS id,
  ('priest:' || p.name)::text AS label
FROM public.priests p
WHERE p.photo_url IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.media_assets m
    WHERE m.bucket = 'priest_photos'
      AND m.storage_path = p.photo_url
  )
UNION ALL
SELECT
  'missing_alt_text'::text AS kind,
  so.created_at AS source_created_at,
  ('x' || substr(replace(so.id::text, '-', ''), 1, 15))::bit(60)::bigint AS id,
  (so.bucket_id || '/' || so.name)::text AS label
FROM storage.objects so
WHERE so.bucket_id IN ('priest_photos', 'church_media', 'announcement_images')
  AND NOT EXISTS (
    SELECT 1 FROM public.media_assets m
    WHERE m.bucket = so.bucket_id
      AND m.storage_path = so.name
  );

REVOKE ALL ON public.v_content_backlog FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.v_content_backlog TO service_role;

-- ==============================================================================
-- 12. RPC: get_backlog
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.get_backlog(
  p_before_created_at timestamptz DEFAULT NULL,
  p_after_id bigint DEFAULT NULL,
  p_limit int DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_limit int;
  v_items jsonb := '[]'::jsonb;
  v_next_cursor jsonb := null;
  v_last_created_at timestamptz;
  v_last_id bigint;
  v_count int;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  v_limit := LEAST(COALESCE(p_limit, 50), 100);
  IF v_limit <= 0 THEN
    v_limit := 50;
  END IF;

  WITH filtered AS (
    SELECT kind, source_created_at, id, label
    FROM public.v_content_backlog
    WHERE (
      p_before_created_at IS NULL
      OR source_created_at < p_before_created_at
      OR (source_created_at = p_before_created_at AND id < p_after_id)
    )
    ORDER BY source_created_at DESC, id DESC
    LIMIT v_limit
  )
  SELECT
    COALESCE(jsonb_agg(to_jsonb(f)), '[]'::jsonb),
    count(*),
    (ARRAY_AGG(f.source_created_at ORDER BY f.source_created_at DESC, f.id DESC))[count(*)],
    (ARRAY_AGG(f.id ORDER BY f.source_created_at DESC, f.id DESC))[count(*)]
  INTO v_items, v_count, v_last_created_at, v_last_id
  FROM filtered f;

  IF v_count = v_limit AND v_last_created_at IS NOT NULL AND v_last_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.v_content_backlog
      WHERE source_created_at < v_last_created_at
         OR (source_created_at = v_last_created_at AND id < v_last_id)
    ) THEN
      v_next_cursor := jsonb_build_object(
        'created_at', to_char(v_last_created_at, 'YYYY-MM-DD"T"HH24:MI:SS.USOF'),
        'id', v_last_id
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'items', v_items,
    'next_cursor', v_next_cursor
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_backlog(timestamptz, bigint, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_backlog(timestamptz, bigint, int) TO authenticated, service_role;

-- ==============================================================================
-- 13. RPC: deliver_personal_video
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.deliver_personal_video(
  p_phone text,
  p_yt_url text,
  p_title_ar text,
  p_payment_id bigint
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_payment public.payments;
  v_booking_user_id uuid;
  v_existing_video_id bigint;
  v_video_id bigint;
  v_purchase_id bigint;
BEGIN
  -- 1. Exact phone match
  SELECT id INTO v_user_id
  FROM public.users
  WHERE phone = p_phone AND deleted_at IS NULL;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'UNKNOWN_PHONE' USING ERRCODE = 'P0002';
  END IF;

  -- 2. Validate payment is PAID and belongs to this user
  SELECT * INTO v_payment
  FROM public.payments
  WHERE id = p_payment_id;

  IF v_payment IS NULL OR v_payment.status <> 'PAID' THEN
    RAISE EXCEPTION 'PAYMENT_INVALID' USING ERRCODE = 'P0001';
  END IF;

  SELECT user_id INTO v_booking_user_id
  FROM public.bookings
  WHERE id = v_payment.booking_id;

  IF v_booking_user_id <> v_user_id THEN
    RAISE EXCEPTION 'PAYMENT_INVALID' USING ERRCODE = 'P0001';
  END IF;

  -- 3. Idempotency: return existing video if already delivered for this payment
  SELECT video_id INTO v_existing_video_id
  FROM public.video_purchases
  WHERE payment_id = p_payment_id;

  IF v_existing_video_id IS NOT NULL THEN
    RETURN v_existing_video_id;
  END IF;

  -- 4. Create UNLISTED video, purchase record, and queue event_outbox WhatsApp notification
  INSERT INTO public.videos (title_ar, event_date, yt_url, price, privacy, tenant_id)
  VALUES (p_title_ar, now(), p_yt_url, 0, 'UNLISTED', public.tenant_id())
  RETURNING id INTO v_video_id;

  INSERT INTO public.video_purchases (video_id, user_id, payment_id, access_granted_at, tenant_id)
  VALUES (v_video_id, v_user_id, p_payment_id, now(), public.tenant_id())
  RETURNING id INTO v_purchase_id;

  INSERT INTO public.event_outbox (handler_type, payload, status, tenant_id)
  VALUES (
    'WHATSAPP',
    jsonb_build_object(
      'template_name', 'video_ready',
      'video_id', v_video_id,
      'purchase_id', v_purchase_id,
      'phone', p_phone
    ),
    'PENDING',
    public.tenant_id()
  );

  RETURN v_video_id;
END;
$$;

REVOKE ALL ON FUNCTION public.deliver_personal_video(text, text, text, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.deliver_personal_video(text, text, text, bigint) TO service_role;




