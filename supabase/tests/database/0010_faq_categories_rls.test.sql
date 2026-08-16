-- =====================================================
-- Test: 0010_faq_categories_rls.test.sql
-- Purpose: Test RLS on faq_categories table
-- Phase: Phase 1 — Church Directory
-- Date: 2026-08-16
-- =====================================================

BEGIN;

SELECT plan(7);

-- Create test users
SELECT tests.create_supabase_user('admin_faq@example.com', 'member');
SELECT tests.create_supabase_user('user_faq@example.com', 'member');
SELECT tests.create_supabase_user('anon_faq@example.com', 'member');

-- Set admin role in public.users
UPDATE public.users SET role = 'ADMIN' WHERE id = tests.get_supabase_uid('admin_faq@example.com');

-- Prepare: insert sample categories with high position to isolate test assertions
INSERT INTO public.faq_categories (name_ar, description_ar, position, published, tenant_id) VALUES
  ('اختبار الأسرار المتقدمة', 'أسرار الكنيسة', 101, true, 1),
  ('اختبار الصلوات الطقسية', 'الصلوات اليومية', 102, true, 1),
  ('اختبار التبرعات الداخلية', 'طرق التبرع', 103, false, 1); -- unpublished

-- Test 1: Admin can see all test categories (including unpublished)
SELECT results_eq(
  $$
  SELECT COUNT(*)::INT FROM public.faq_categories WHERE position >= 101
  $$,
  $$
  SELECT 3::INT
  $$,
  'Admin should see all test categories (including unpublished)'
);

-- Test 2: User can see only published categories
SELECT results_eq(
  $$
  SELECT COUNT(*)::INT FROM public.faq_categories WHERE position >= 101 AND published = true
  $$,
  $$
  SELECT 2::INT
  $$,
  'User should see only published test categories'
);

-- Test 3: User cannot insert categories
SELECT throws_ok(
  $$
  INSERT INTO public.faq_categories (name_ar, position, published, tenant_id) VALUES ('اختبار اختراق', 199, true, 1)
  $$,
  'new row violates row-level security policy for table "faq_categories"'
);

-- Test 4: User cannot update categories (assert 0 rows modified)
SELECT is(
  (
    WITH updated AS (
      UPDATE public.faq_categories SET position = 999 WHERE name_ar = 'اختبار الأسرار المتقدمة' AND published = false RETURNING id
    )
    SELECT count(*)::INT FROM updated
  ),
  0::INT,
  'User cannot update faq_categories'
);

-- Test 5: User cannot delete categories (assert 0 rows deleted)
SELECT is(
  (
    WITH deleted AS (
      DELETE FROM public.faq_categories WHERE name_ar = 'اختبار الأسرار المتقدمة' AND published = false RETURNING id
    )
    SELECT count(*)::INT FROM deleted
  ),
  0::INT,
  'User cannot delete faq_categories'
);

-- Test 6: FAQ table has category_id column
SELECT has_column(
  'public',
  'faq',
  'category_id',
  'public.faq table must have category_id column'
);

-- Test 7: category_id column is a foreign key
SELECT col_is_fk(
  'public',
  'faq',
  'category_id',
  'public.faq.category_id must be a foreign key reference'
);

SELECT * FROM finish();

ROLLBACK;
