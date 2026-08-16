-- supabase/tests/0043_faq_categories_test.sql
-- Test faq_categories and faq.category_id RLS policies

BEGIN;

DO $$
DECLARE
  v_admin_id uuid := '00000000-0000-0000-0000-000000000043';
  v_user_id  uuid := '00000000-0000-0000-0000-000000000044';
  v_cat_id   bigint;
  v_count    int;
BEGIN
  -- 0. Seed test users
  INSERT INTO auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES
    (v_admin_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a43@test.local', '+201099990043', '{}', '{}', now(), now()),
    (v_user_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'u44@test.local', '+201099990044', '{}', '{}', now(), now())
  ON CONFLICT (id) DO NOTHING;
  UPDATE public.users SET role = 'ADMIN', tenant_id = 1, deleted_at = null WHERE id = v_admin_id;
  UPDATE public.users SET role = 'USER', tenant_id = 1, deleted_at = null WHERE id = v_user_id;

  -- 1. Admin creates active and unpublished categories
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id, 'role', 'authenticated')::text, true);

  INSERT INTO public.faq_categories (name_ar, description_ar, position, published, tenant_id)
  VALUES ('الأسرار الإضافية', 'أسرار الكنيسة', 10, true, 1)
  RETURNING id INTO v_cat_id;

  INSERT INTO public.faq_categories (name_ar, description_ar, position, published, tenant_id)
  VALUES ('مسودة داخلية', 'فئة قيد الإعداد', 20, false, 1);

  -- 2. Anonymous / User checks
  SET LOCAL ROLE anon;
  -- Can read published category
  SELECT count(*) INTO v_count FROM public.faq_categories WHERE id = v_cat_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: anon must see published category, got %', v_count;
  END IF;

  -- Cannot see unpublished category
  SELECT count(*) INTO v_count FROM public.faq_categories WHERE name_ar = 'مسودة داخلية';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: anon must NOT see unpublished category';
  END IF;

  -- Anon cannot insert (catch insufficient_privilege 42501)
  BEGIN
    INSERT INTO public.faq_categories (name_ar, position, published, tenant_id)
    VALUES ('محاولة اختراق', 99, true, 1);
    RAISE EXCEPTION 'FAIL: anon must NOT be allowed to insert faq_categories';
  EXCEPTION 
    WHEN SQLSTATE '42501' THEN
      NULL; -- expected permission denial
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%FAIL: anon must NOT%' THEN RAISE; END IF;
  END;

  -- 3. Regular USER checks
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_id, 'role', 'authenticated')::text, true);

  -- USER cannot insert (violates RLS WITH CHECK)
  BEGIN
    INSERT INTO public.faq_categories (name_ar, position, published, tenant_id)
    VALUES ('محاولة مستخدم', 99, true, 1);
    RAISE EXCEPTION 'FAIL: regular user must NOT be allowed to insert faq_categories';
  EXCEPTION 
    WHEN SQLSTATE '42501' THEN
      NULL;
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%FAIL: regular user must NOT%' THEN RAISE; END IF;
  END;

  -- USER cannot update (affects 0 rows due to RLS USING)
  UPDATE public.faq_categories SET position = 99 WHERE id = v_cat_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: regular user must NOT be allowed to update faq_categories, updated % rows', v_count;
  END IF;

  -- USER cannot delete (affects 0 rows due to RLS USING)
  DELETE FROM public.faq_categories WHERE id = v_cat_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: regular user must NOT be allowed to delete faq_categories, deleted % rows', v_count;
  END IF;

  -- 4. Admin updates
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id, 'role', 'authenticated')::text, true);
  UPDATE public.faq_categories SET description_ar = 'تعديل الوصف من الإدارة' WHERE id = v_cat_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: admin must be able to update faq_categories, updated % rows', v_count;
  END IF;

  -- 5. Verify sequence privilege for authenticated role
  RESET ROLE;
  IF pg_get_serial_sequence('public.faq_categories', 'id') IS NOT NULL THEN
    IF NOT has_sequence_privilege('authenticated', pg_get_serial_sequence('public.faq_categories', 'id'), 'USAGE') THEN
      RAISE EXCEPTION 'FAIL: authenticated role must have USAGE privilege on faq_categories identity sequence';
    END IF;
  END IF;

  RESET ROLE;
  RAISE NOTICE '0043_faq_categories_test: OK';
END $$;

ROLLBACK;
