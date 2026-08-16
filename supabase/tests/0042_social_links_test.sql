-- supabase/tests/0042_social_links_test.sql
-- Test social_links RLS policies (public read active, admin-only write)

DO $$
DECLARE
  v_admin_id uuid := '00000000-0000-0000-0000-000000000041';
  v_user_id  uuid := '00000000-0000-0000-0000-000000000042';
  v_link_id  bigint;
  v_count    int;
BEGIN
  -- 0. Seed test users
  INSERT INTO public.users (id, phone, name, role, tenant_id)
  VALUES 
    (v_admin_id, '+201099990041', 'Admin 42', 'ADMIN', 1),
    (v_user_id,  '+201099990042', 'User 42', 'USER', 1)
  ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, phone = EXCLUDED.phone;

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

  -- USER cannot update
  BEGIN
    UPDATE public.social_links SET title_ar = 'تعديل غير مصرح' WHERE id = v_link_id;
    RAISE EXCEPTION 'FAIL: regular user must NOT be allowed to update social_links';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FAIL: regular user must NOT%' THEN RAISE; END IF;
  END;

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
