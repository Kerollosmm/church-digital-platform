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

