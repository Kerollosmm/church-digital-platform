-- =====================================================
-- Migration: 0043_faq_categories.sql
-- Purpose: Add faq_categories table and link faq to categories
-- Phase: Phase 1 — Church Directory
-- Date: 2026-08-16
-- =====================================================

-- 1. Create faq_categories table
CREATE TABLE IF NOT EXISTS public.faq_categories (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name_ar TEXT NOT NULL,
  description_ar TEXT,
  position INT NOT NULL DEFAULT 0,
  published BOOLEAN NOT NULL DEFAULT true,
  tenant_id BIGINT NOT NULL DEFAULT public.tenant_id(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  CONSTRAINT faq_categories_name_unique UNIQUE (name_ar, tenant_id)
);

-- 2. Enable RLS
ALTER TABLE public.faq_categories ENABLE ROW LEVEL SECURITY;

-- 3. RLS Policies

-- Admins can do everything
DROP POLICY IF EXISTS "Admins can do everything on faq_categories" ON public.faq_categories;
CREATE POLICY "Admins can do everything on faq_categories"
  ON public.faq_categories
  FOR ALL
  TO authenticated
  USING (
    public.is_admin()
    AND tenant_id = public.tenant_id()
  )
  WITH CHECK (
    public.is_admin()
    AND tenant_id = public.tenant_id()
  );

-- Users can read only published categories
DROP POLICY IF EXISTS "Users can read published categories" ON public.faq_categories;
CREATE POLICY "Users can read published categories"
  ON public.faq_categories
  FOR SELECT
  TO anon, authenticated
  USING (
    published = true
    AND tenant_id = public.tenant_id()
  );

-- 4. Add category_id to faq table
ALTER TABLE public.faq
ADD COLUMN IF NOT EXISTS category_id BIGINT REFERENCES public.faq_categories(id) ON DELETE SET NULL;

-- 5. Add index for faster filtering
CREATE INDEX IF NOT EXISTS idx_faq_category_id ON public.faq(category_id);

-- 6. Add comments
COMMENT ON TABLE public.faq_categories IS 'Categories for classifying FAQs (e.g., "الأسرار", "الصلوات", "الخدمات")';
COMMENT ON COLUMN public.faq_categories.name_ar IS 'Arabic name of the category';
COMMENT ON COLUMN public.faq_categories.description_ar IS 'Optional Arabic description of the category';
COMMENT ON COLUMN public.faq_categories.position IS 'Display order in the UI';
COMMENT ON COLUMN public.faq_categories.published IS 'Whether the category is visible to users';
COMMENT ON COLUMN public.faq.category_id IS 'Reference to faq_categories (NULL = uncategorized)';

-- 7. Seed sample data (optional, for testing)
INSERT INTO public.faq_categories (name_ar, description_ar, position, published, tenant_id) VALUES
  ('الأسرار', 'أسرار الكنيسة السبعة', 1, true, 1),
  ('الصلوات', 'الصلوات اليومية والأسبوعية', 2, true, 1),
  ('الخدمات', 'مواعيد الخدمات والقداسات', 3, true, 1),
  ('التبرعات', 'طرق التبرع والخدمة الاجتماعية', 4, true, 1),
  ('الزيارات', 'مواعيد زيارة الكهنة والمناسبات', 5, true, 1)
ON CONFLICT (name_ar, tenant_id) DO NOTHING;

-- 8. Grants and sequence permissions
GRANT SELECT ON public.faq_categories TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.faq_categories TO authenticated;

DO $$
DECLARE
  v_seq text;
BEGIN
  v_seq := pg_get_serial_sequence('public.faq_categories', 'id');
  IF v_seq IS NOT NULL THEN
    EXECUTE 'GRANT USAGE, SELECT ON SEQUENCE ' || v_seq || ' TO authenticated';
  END IF;
END $$;
