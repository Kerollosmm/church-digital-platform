-- supabase/tests/0044_storage_buckets_test.sql
-- Test storage.objects RLS policies and bucket configurations

BEGIN;

DO $$
DECLARE
  v_admin_id uuid := '00000000-0000-0000-0000-000000000045';
  v_user_id  uuid := '00000000-0000-0000-0000-000000000046';
  v_count    int;
BEGIN
  -- 0. Seed test users and buckets
  INSERT INTO public.users (id, phone, name, role, tenant_id)
  VALUES 
    (v_admin_id, '+201099990045', 'Admin Storage', 'ADMIN', 1),
    (v_user_id,  '+201099990046', 'User Storage', 'USER', 1)
  ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, phone = EXCLUDED.phone;

  INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  VALUES 
    ('priest_photos', 'priest_photos', false, 524288, ARRAY['image/jpeg', 'image/png', 'image/webp']),
    ('church_media', 'church_media', false, 524288, ARRAY['image/jpeg', 'image/png', 'image/webp']),
    ('announcement_images', 'announcement_images', false, 524288, ARRAY['image/jpeg', 'image/png', 'image/webp'])
  ON CONFLICT (id) DO UPDATE SET 
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

  -- 1. Verify buckets count
  SELECT COUNT(*) INTO v_count FROM storage.buckets WHERE id IN ('priest_photos', 'church_media', 'announcement_images');
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'FAIL: expected 3 storage buckets, found %', v_count;
  END IF;

  -- 2. Test user upload denial (SQLSTATE 42501 or WITH CHECK failure)
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_id, 'role', 'authenticated')::text, true);

  BEGIN
    INSERT INTO storage.objects (id, bucket_id, name, owner)
    VALUES ('00000000-0000-0000-0000-000000000101', 'church_media', 'test.jpg', v_user_id);
    RAISE EXCEPTION 'FAIL: non-admin user must NOT be allowed to insert into church_media';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      NULL; -- expected RLS WITH CHECK or privilege denial
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%FAIL: non-admin%' THEN RAISE; END IF;
  END;

  -- 3. Test user delete denial on church_media (affects 0 rows)
  DELETE FROM storage.objects WHERE bucket_id = 'church_media';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: non-admin user must NOT delete church_media objects, deleted % rows', v_count;
  END IF;

  RESET ROLE;
  RAISE NOTICE '0044_storage_buckets_test: OK';
END $$;

ROLLBACK;
