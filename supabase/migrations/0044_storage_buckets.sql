-- =====================================================
-- Migration: 0044_storage_buckets.sql
-- Purpose: Add 3 storage buckets for images (priest_photos, church_media, announcement_images)
-- Phase: Phase 1 — Church Directory
-- Date: 2026-08-16
-- =====================================================

-- Note: Supabase Storage buckets are created via the storage schema, not public schema.
-- This migration creates buckets and sets up RLS policies.

-- 1. Create priest_photos bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'priest_photos',
  'priest_photos',
  false, -- private bucket (access controlled via RLS)
  524288, -- 512KB max per file (free plan limit: 1GB total)
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- 2. Create church_media bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'church_media',
  'church_media',
  false, -- private bucket
  524288, -- 512KB max per file
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- 3. Create announcement_images bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'announcement_images',
  'announcement_images',
  false, -- private bucket
  524288, -- 512KB max per file
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- 4. Enable RLS on storage.objects
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- priest_photos bucket policies
-- =====================================================

DROP POLICY IF EXISTS "Admins can upload priest photos" ON storage.objects;
CREATE POLICY "Admins can upload priest photos"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'priest_photos'
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Admins can update priest photos" ON storage.objects;
CREATE POLICY "Admins can update priest photos"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'priest_photos'
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Admins can delete priest photos" ON storage.objects;
CREATE POLICY "Admins can delete priest photos"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'priest_photos'
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Users can read priest photos" ON storage.objects;
CREATE POLICY "Users can read priest photos"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'priest_photos'
  );

-- =====================================================
-- church_media bucket policies
-- =====================================================

DROP POLICY IF EXISTS "Admins can upload church media" ON storage.objects;
CREATE POLICY "Admins can upload church media"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'church_media'
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Admins can update church media" ON storage.objects;
CREATE POLICY "Admins can update church media"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'church_media'
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Admins can delete church media" ON storage.objects;
CREATE POLICY "Admins can delete church media"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'church_media'
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Users can read church media" ON storage.objects;
CREATE POLICY "Users can read church media"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'church_media'
  );

-- =====================================================
-- announcement_images bucket policies
-- =====================================================

DROP POLICY IF EXISTS "Admins can upload announcement images" ON storage.objects;
CREATE POLICY "Admins can upload announcement images"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'announcement_images'
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Admins can update announcement images" ON storage.objects;
CREATE POLICY "Admins can update announcement images"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'announcement_images'
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Admins can delete announcement images" ON storage.objects;
CREATE POLICY "Admins can delete announcement images"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'announcement_images'
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Users can read announcement images" ON storage.objects;
CREATE POLICY "Users can read announcement images"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'announcement_images'
  );

-- 5. Add comments
COMMENT ON TABLE storage.buckets IS 'Supabase Storage buckets (created via SQL migration)';
COMMENT ON COLUMN storage.objects.bucket_id IS 'Bucket identifier (priest_photos, church_media, announcement_images)';

-- 6. Grant least-privilege usage to authenticated users
GRANT USAGE ON SCHEMA storage TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON storage.objects TO authenticated;
GRANT SELECT ON storage.buckets TO authenticated;
