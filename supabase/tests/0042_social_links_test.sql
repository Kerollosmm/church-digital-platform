BEGIN;

DO $$
DECLARE
  v_admin_id uuid := '00000000-0000-0000-0000-000000000041';
  v_user_id  uuid := '00000000-0000-0000-0000-000000000042';
  v_link_id  bigint;
  v_count    int;
BEGIN
  -- 0. Seed test users
  INSERT INTO auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES
    (v_admin_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a42@test.local', '+201099990041', '{}', '{}', now(), now()),
    (v_user_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'u42@test.local', '+201099990042', '{}', '{}', now(), now())
  ON CONFLICT (id) DO NOTHING;
  UPDATE public.users SET role = 'ADMIN', tenant_id = 1, deleted_at = null WHERE id = v_admin_id;
  UPDATE public.users SET role = 'USER', tenant_id = 1, deleted_at = null WHERE id = v_user_id;

  -- 1. Admin creates active and inactive social links
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id, 'role', 'authenticated')::text, true);

  INSERT INTO public.social_links (platform, title_ar, url, is_active, tenant_id)
  VALUES ('YOUTUBE', 'قناة الكنيسة الرسمية', 'https://youtube.com/@church', true, 1)
  RETURNING id INTO v_link_id;

  INSERT INTO public.social_links (platform, title_ar, url, is_active, tenant_id)
  VALUES ('FACEBOOK', 'صفحة فيسبوك القديمة', 'https://facebook.com/old', false, 1);

  -- 2. Anonymous user checks
  SET LOCAL ROLE anon;
  -- Can read active link
  SELECT count(*) INTO v_count FROM public.social_links WHERE id = v_link_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: anon must see active social link, got %', v_count;
  END IF;

  -- Cannot see inactive link
  SELECT count(*) INTO v_count FROM public.social_links WHERE platform = 'FACEBOOK' AND is_active = false;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: anon must NOT see inactive social link';
  END IF;

  -- Cannot insert
  BEGIN
    INSERT INTO public.social_links (platform, title_ar, url, is_active, tenant_id)
    VALUES ('TWITTER', 'تويتر', 'https://x.com/church', true, 1);
    RAISE EXCEPTION 'FAIL: anon must NOT be allowed to insert social_links';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FAIL: anon must NOT%' THEN RAISE; END IF;
  END;

  -- 3. Regular USER checks
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_id, 'role', 'authenticated')::text, true);

  -- USER can read active
  SELECT count(*) INTO v_count FROM public.social_links WHERE id = v_link_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: regular user must see active social link';
  END IF;

  -- USER cannot insert
  BEGIN
    INSERT INTO public.social_links (platform, title_ar, url, is_active, tenant_id)
    VALUES ('INSTAGRAM', 'انستجرام', 'https://instagram.com/church', true, 1);
    RAISE EXCEPTION 'FAIL: regular user must NOT be allowed to insert social_links';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FAIL: regular user must NOT%' THEN RAISE; END IF;
  END;

  -- USER cannot update (affects 0 rows due to RLS USING)
  UPDATE public.social_links SET title_ar = 'تعديل غير مصرح' WHERE id = v_link_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: regular user update must affect 0 rows, affected %', v_count;
  END IF;

  -- 4. Admin updates and deletes
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id, 'role', 'authenticated')::text, true);

  UPDATE public.social_links SET title_ar = 'قناة الكنيسة على يوتيوب' WHERE id = v_link_id;
  SELECT count(*) INTO v_count FROM public.social_links WHERE id = v_link_id AND title_ar = 'قناة الكنيسة على يوتيوب';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: admin must be able to update social_links';
  END IF;

  -- 5. Verify sequence privilege for authenticated role
  RESET ROLE;
  IF pg_get_serial_sequence('public.social_links', 'id') IS NOT NULL THEN
    IF NOT has_sequence_privilege('authenticated', pg_get_serial_sequence('public.social_links', 'id'), 'USAGE') THEN
      RAISE EXCEPTION 'FAIL: authenticated role must have USAGE privilege on social_links identity sequence';
    END IF;
  END IF;

  RESET ROLE;
  RAISE NOTICE '0042_social_links_test: OK';
END $$;

ROLLBACK;
