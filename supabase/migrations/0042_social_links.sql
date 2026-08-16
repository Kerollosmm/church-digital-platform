-- 0042: social_links table for church directory (Phase 1)
-- Provides official social media, streaming channels, contact links, and maps location.

CREATE TABLE IF NOT EXISTS public.social_links (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  platform TEXT NOT NULL,
  title_ar TEXT NOT NULL,
  url TEXT NOT NULL,
  icon_name TEXT,
  position INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

ALTER TABLE public.social_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "social_links public read" ON public.social_links;
CREATE POLICY "social_links public read" ON public.social_links
  FOR SELECT TO anon, authenticated
  USING (is_active = true AND deleted_at IS NULL AND tenant_id = public.tenant_id());

DROP POLICY IF EXISTS "social_links admin all" ON public.social_links;
CREATE POLICY "social_links admin all" ON public.social_links
  FOR ALL TO authenticated
  USING (public.is_admin() AND tenant_id = public.tenant_id())
  WITH CHECK (public.is_admin() AND tenant_id = public.tenant_id());

GRANT SELECT ON public.social_links TO anon, authenticated;
GRANT ALL ON public.social_links TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

DO $$
DECLARE
  v_seq text;
BEGIN
  v_seq := pg_get_serial_sequence('public.social_links', 'id');
  IF v_seq IS NOT NULL THEN
    EXECUTE 'GRANT USAGE, SELECT ON SEQUENCE ' || v_seq || ' TO authenticated';
  END IF;
END $$;

COMMENT ON TABLE public.social_links IS 'Official church social links, map directions, and contact channels for public directory and mobile portal.';
