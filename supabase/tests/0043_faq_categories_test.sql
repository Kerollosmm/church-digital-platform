-- supabase/tests/0043_faq_categories_test.sql
-- Test faq_categories and faq.category_id RLS policies

DO $$
DECLARE
  v_admin_id uuid := '00000000-0000-0000-0000-000000000043';
  v_user_id  uuid := '00000000-0000-0000-0000-000000000044';
  v_cat_id   bigint;
  v_count    int;
BEGIN
  -- 0. Seed test users
  INSERT INTO public.users (id, phone, name, role, tenant_id)
  VALUES 
    (v_admin_id, '+201099990043', 'Admin 43', 'ADMIN', 1),
    (v_user_id,  '+201099990044', 'User 44', 'USER', 1)
  ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, phone = EXCLUDED.phone;

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

  -- Anon cannot insert
  BEGIN
    INSERT INTO public.faq_categories (name_ar, position, published, tenant_id)
    VALUES ('محاولة اختراق', 99, true, 1);
    RAISE EXCEPTION 'FAIL: anon must NOT be allowed to insert faq_categories';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FAIL: anon must NOT%' THEN RAISE; END IF;
  END;

  -- 3. Regular USER checks
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_id, 'role', 'authenticated')::text, true);

  -- USER cannot insert
  BEGIN
    INSERT INTO public.faq_categories (name_ar, position, published, tenant_id)
    VALUES ('محاولة مستخدم', 99, true, 1);
    RAISE EXCEPTION 'FAIL: regular user must NOT be allowed to insert faq_categories';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FAIL: regular user must NOT%' THEN RAISE; END IF;
  END;

  -- USER cannot update
  BEGIN
    UPDATE public.faq_categories SET position = 99 WHERE id = v_cat_id;
    RAISE EXCEPTION 'FAIL: regular user must NOT be allowed to update faq_categories';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FAIL: regular user must NOT%' THEN RAISE; END IF;
  END;

  -- USER cannot delete
  BEGIN
    DELETE FROM public.faq_categories WHERE id = v_cat_id;
    RAISE EXCEPTION 'FAIL: regular user must NOT be allowed to delete faq_categories';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FAIL: regular user must NOT%' THEN RAISE; END IF;
  END;

  -- 4. Admin updates
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id, 'role', 'authenticated')::text, true);
  UPDATE public.faq_categories SET description_ar = 'تعديل الوصف من الإدارة' WHERE id = v_cat_id;
  SELECT count(*) INTO v_count FROM public.faq_categories WHERE id = v_cat_id AND description_ar = 'تعديل الوصف من الإدارة';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: admin must be able to update faq_categories';
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
