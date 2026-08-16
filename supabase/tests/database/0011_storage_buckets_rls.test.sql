-- =====================================================
-- Test: 0011_storage_buckets_rls.test.sql
-- Purpose: Test RLS on storage buckets
-- Phase: Phase 1 — Church Directory
-- Date: 2026-08-16
-- =====================================================

BEGIN;

SELECT plan(9);

-- Create test users
SELECT tests.create_supabase_user('admin_storage@example.com', 'member');
SELECT tests.create_supabase_user('user_storage@example.com', 'member');

-- Set admin role
UPDATE public.profiles SET role = 'ADMIN' WHERE id = tests.get_supabase_uid('admin_storage@example.com');

-- Test 1: Buckets exist
SELECT results_eq(
  $$
  SELECT COUNT(*)::INT FROM storage.buckets WHERE id IN ('priest_photos', 'church_media', 'announcement_images')
  $$,
  $$
  SELECT 3::INT
  $$,
  'All 3 buckets should exist'
);

-- Test 2: Admin can insert into priest_photos bucket
-- Note: We can't actually upload files in pgTAP, but we can verify policies exist.
SELECT has_policy(
  'storage.objects',
  'Admins can upload priest photos',
  'Policy for admin upload to priest_photos should exist'
);

-- Test 3: Users can read priest_photos bucket
SELECT has_policy(
  'storage.objects',
  'Users can read priest photos',
  'Policy for user read from priest_photos should exist'
);

-- Test 4: Admin can insert into church_media bucket
SELECT has_policy(
  'storage.objects',
  'Admins can upload church media',
  'Policy for admin upload to church_media should exist'
);

-- Test 5: Users can read church_media bucket
SELECT has_policy(
  'storage.objects',
  'Users can read church media',
  'Policy for user read from church_media should exist'
);

-- Test 6: Admin can insert into announcement_images bucket
SELECT has_policy(
  'storage.objects',
  'Admins can upload announcement images',
  'Policy for admin upload to announcement_images should exist'
);

-- Test 7: Users can read announcement_images bucket
SELECT has_policy(
  'storage.objects',
  'Users can read announcement images',
  'Policy for user read from announcement_images should exist'
);

-- Test 8: Bucket file size limits are set
SELECT results_eq(
  $$
  SELECT file_size_limit::INT FROM storage.buckets WHERE id = 'priest_photos'
  $$,
  $$
  SELECT 524288::INT
  $$,
  'priest_photos bucket should have 512KB file size limit'
);

-- Test 9: Bucket allowed mime types are set
SELECT results_eq(
  $$
  SELECT allowed_mime_types FROM storage.buckets WHERE id = 'priest_photos'
  $$,
  $$
  SELECT ARRAY['image/jpeg', 'image/png', 'image/webp']::TEXT[]
  $$,
  'priest_photos bucket should allow only image/jpeg, image/png, image/webp'
);

SELECT * FROM finish();

ROLLBACK;
