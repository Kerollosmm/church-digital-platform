-- =====================================================
-- Test: 0010_faq_categories_rls.test.sql
-- Purpose: Test RLS on faq_categories table
-- Phase: Phase 1 — Church Directory
-- Date: 2026-08-16
-- =====================================================

BEGIN;

SELECT plan(6);

-- Create test users
SELECT tests.create_supabase_user('admin_faq@example.com', 'member');
SELECT tests.create_supabase_user('user_faq@example.com', 'member');
SELECT tests.create_supabase_user('anon_faq@example.com', 'member');

-- Set admin role
UPDATE public.profiles SET role = 'ADMIN' WHERE id = tests.get_supabase_uid('admin_faq@example.com');

-- Prepare: insert sample categories
INSERT INTO public.faq_categories (name_ar, description_ar, position, published, tenant_id) VALUES
  ('الأسرار', 'أسرار الكنيسة السبعة', 1, true, 1),
  ('الصلوات', 'الصلوات اليومية والأسبوعية', 2, true, 1),
  ('التبرعات', 'طرق التبرع', 3, false, 1); -- unpublished

-- Test 1: Admin can see all categories (including unpublished)
SELECT results_eq(
  $$
  SELECT COUNT(*)::INT FROM public.faq_categories
  $$,
  $$
  SELECT 3::INT
  $$,
  'Admin should see all categories (including unpublished)'
);

-- Test 2: User can see only published categories
SELECT results_eq(
  $$
  SELECT COUNT(*)::INT FROM public.faq_categories WHERE published = true
  $$,
  $$
  SELECT 2::INT
  $$,
  'User should see only published categories'
);

-- Test 3: User cannot insert categories
SELECT throws_ok(
  $$
  INSERT INTO public.faq_categories (name_ar, position, published, tenant_id) VALUES ('Test', 99, true, 1)
  $$,
  'new row violates row-level security policy for table "faq_categories"'
);

-- Test 4: User cannot update categories
SELECT throws_ok(
  $$
  UPDATE public.faq_categories SET position = 99 WHERE name_ar = 'الأسرار'
  $$,
  'new row violates row-level security policy for table "faq_categories"'
);

-- Test 5: User cannot delete categories
SELECT throws_ok(
  $$
  DELETE FROM public.faq_categories WHERE name_ar = 'الأسرار'
  $$,
  'new row violates row-level security policy for table "faq_categories"'
);

-- Test 6: FAQ with category_id works
SELECT results_eq(
  $$
  SELECT COUNT(*)::INT FROM public.faq WHERE category_id IS NOT NULL
  $$,
  $$
  SELECT 0::INT
  $$,
  'FAQs should have NULL category_id initially (no migration updated them yet)'
);

SELECT * FROM finish();

ROLLBACK;
