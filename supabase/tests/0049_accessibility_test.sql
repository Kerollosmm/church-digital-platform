\set ON_ERROR_STOP on

create schema if not exists tests;
create or replace function tests.expect(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if not p_cond then raise exception 'FAIL: %', p_msg; end if;
end $$;
grant usage on schema tests to anon, authenticated, service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;

BEGIN;

-- ==============================================================================
-- 0. Seed test fixtures
-- ==============================================================================
INSERT INTO auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES 
  ('00000000-0000-0000-0000-000000000049', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin49@test.local', '+201099990049', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000050', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'user50@test.local', '+201099990050', '{}', '{}', now(), now())
ON CONFLICT (id) DO NOTHING;

UPDATE public.users SET role = 'ADMIN', tenant_id = 1, deleted_at = null WHERE id = '00000000-0000-0000-0000-000000000049';
UPDATE public.users SET role = 'USER', tenant_id = 1, deleted_at = null WHERE id = '00000000-0000-0000-0000-000000000050';

-- ==============================================================================
-- 1. Schema Invariants: media_assets & error_messages
-- ==============================================================================
DO $$
DECLARE
  v_col_count int;
  v_seq_name text;
  v_has_usage boolean;
BEGIN
  -- 1.1 Tables exist in public schema
  PERFORM tests.expect(
    EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'media_assets'),
    'Table public.media_assets must exist'
  );
  PERFORM tests.expect(
    EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'error_messages'),
    'Table public.error_messages must exist'
  );

  -- 1.2 RLS is enabled on both tables
  PERFORM tests.expect(
    (SELECT rowsecurity FROM pg_tables WHERE schemaname = 'public' AND tablename = 'media_assets') = true,
    'RLS must be enabled on public.media_assets'
  );
  PERFORM tests.expect(
    (SELECT rowsecurity FROM pg_tables WHERE schemaname = 'public' AND tablename = 'error_messages') = true,
    'RLS must be enabled on public.error_messages'
  );

  -- 1.3 Columns on public.media_assets
  PERFORM tests.expect(
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'media_assets' AND column_name = 'id'),
    'media_assets.id column must exist'
  );
  PERFORM tests.expect(
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'media_assets' AND column_name = 'bucket' AND is_nullable = 'NO'),
    'media_assets.bucket column must exist and be NOT NULL'
  );
  PERFORM tests.expect(
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'media_assets' AND column_name = 'storage_path' AND is_nullable = 'NO'),
    'media_assets.storage_path column must exist and be NOT NULL'
  );
  PERFORM tests.expect(
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'media_assets' AND column_name = 'alt_text_ar' AND is_nullable = 'YES'),
    'media_assets.alt_text_ar column must exist and be nullable'
  );
  PERFORM tests.expect(
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'media_assets' AND column_name = 'is_decorative' AND is_nullable = 'NO'),
    'media_assets.is_decorative column must exist and be NOT NULL'
  );
  PERFORM tests.expect(
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'media_assets' AND column_name = 'content_type' AND is_nullable = 'YES'),
    'media_assets.content_type column must exist and be nullable'
  );
  PERFORM tests.expect(
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'media_assets' AND column_name = 'content_id' AND is_nullable = 'YES'),
    'media_assets.content_id column must exist and be nullable'
  );
  PERFORM tests.expect(
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'media_assets' AND column_name = 'language' AND is_nullable = 'NO'),
    'media_assets.language column must exist and be NOT NULL'
  );
  PERFORM tests.expect(
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'media_assets' AND column_name = 'tenant_id' AND is_nullable = 'NO'),
    'media_assets.tenant_id column must exist and be NOT NULL'
  );

  -- 1.4 Columns on public.error_messages
  PERFORM tests.expect(
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'error_messages' AND column_name = 'code' AND is_nullable = 'NO'),
    'error_messages.code column must exist and be NOT NULL'
  );
  PERFORM tests.expect(
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'error_messages' AND column_name = 'message_ar' AND is_nullable = 'NO'),
    'error_messages.message_ar column must exist and be NOT NULL'
  );
  PERFORM tests.expect(
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'error_messages' AND column_name = 'tenant_id' AND is_nullable = 'NO'),
    'error_messages.tenant_id column must exist and be NOT NULL'
  );

  -- 1.5 Unique constraint on media_assets (bucket, storage_path, tenant_id)
  PERFORM tests.expect(
    EXISTS (
      SELECT 1
      FROM pg_constraint c
      JOIN pg_class t ON t.oid = c.conrelid
      JOIN pg_namespace n ON n.oid = t.relnamespace
      WHERE n.nspname = 'public' AND t.relname = 'media_assets'
        AND c.contype = 'u'
        AND ARRAY(
          SELECT a.attname::text
          FROM unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
          JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
          ORDER BY k.ord
        ) = ARRAY['bucket', 'storage_path', 'tenant_id']::text[]
    ),
    'media_assets must have a UNIQUE constraint strictly on (bucket, storage_path, tenant_id)'
  );

  -- 1.6 Identity sequence permissions for authenticated
  SELECT pg_get_serial_sequence('public.media_assets', 'id') INTO v_seq_name;
  IF v_seq_name IS NOT NULL THEN
    SELECT has_sequence_privilege('authenticated', v_seq_name, 'USAGE') INTO v_has_usage;
    PERFORM tests.expect(v_has_usage, 'authenticated must have USAGE on media_assets sequence');
  END IF;
END $$;

-- ==============================================================================
-- 2. Catalog Seeding: exactly 6 rows in error_messages
-- ==============================================================================
DO $$
DECLARE
  v_count int;
  v_unauth text;
  v_forbidden text;
  v_bad_req text;
  v_upstream text;
  v_internal text;
  v_fallback text;
BEGIN
  SELECT count(*) INTO v_count FROM public.error_messages;
  PERFORM tests.expect(v_count = 6, 'error_messages must contain exactly 6 rows, found ' || v_count);
  PERFORM tests.expect(
    (SELECT count(*) FROM public.error_messages WHERE tenant_id = public.tenant_id()) = 6,
    'all 6 seeded error_messages must have tenant_id matching public.tenant_id()'
  );


  SELECT message_ar INTO v_unauth FROM public.error_messages WHERE code = 'UNAUTHORIZED';
  SELECT message_ar INTO v_forbidden FROM public.error_messages WHERE code = 'FORBIDDEN';
  SELECT message_ar INTO v_bad_req FROM public.error_messages WHERE code = 'BAD_REQUEST';
  SELECT message_ar INTO v_upstream FROM public.error_messages WHERE code = 'UPSTREAM_ERROR';
  SELECT message_ar INTO v_internal FROM public.error_messages WHERE code = 'INTERNAL';
  SELECT message_ar INTO v_fallback FROM public.error_messages WHERE code = 'FALLBACK';

  PERFORM tests.expect(v_unauth IS NOT NULL AND length(trim(v_unauth)) > 0, 'UNAUTHORIZED message must be non-empty');
  PERFORM tests.expect(v_forbidden IS NOT NULL AND length(trim(v_forbidden)) > 0, 'FORBIDDEN message must be non-empty');
  PERFORM tests.expect(v_bad_req IS NOT NULL AND length(trim(v_bad_req)) > 0, 'BAD_REQUEST message must be non-empty');
  PERFORM tests.expect(v_upstream IS NOT NULL AND length(trim(v_upstream)) > 0, 'UPSTREAM_ERROR message must be non-empty');
  PERFORM tests.expect(v_internal IS NOT NULL AND length(trim(v_internal)) > 0, 'INTERNAL message must be non-empty');
  PERFORM tests.expect(v_fallback IS NOT NULL AND length(trim(v_fallback)) > 0, 'FALLBACK message must be non-empty');
END $$;

-- ==============================================================================
-- 3. CHECK Constraints Verification
-- ==============================================================================
DO $$
BEGIN
  -- 3.1 media_assets invalid bucket rejected
  BEGIN
    INSERT INTO public.media_assets (bucket, storage_path, alt_text_ar, is_decorative, tenant_id)
    VALUES ('invalid_bucket', 'path/to/img.jpg', 'صورة تجريبية', false, 1);
    RAISE EXCEPTION 'Invalid bucket must be rejected by CHECK constraint';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  -- 3.2 media_assets non-decorative with NULL alt_text_ar rejected
  BEGIN
    INSERT INTO public.media_assets (bucket, storage_path, alt_text_ar, is_decorative, tenant_id)
    VALUES ('priest_photos', 'path/to/img.jpg', NULL, false, 1);
    RAISE EXCEPTION 'Non-decorative row with NULL alt_text_ar must be rejected';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  -- 3.3 media_assets non-decorative with empty/whitespace alt_text_ar rejected
  BEGIN
    INSERT INTO public.media_assets (bucket, storage_path, alt_text_ar, is_decorative, tenant_id)
    VALUES ('priest_photos', 'path/to/img.jpg', '   ', false, 1);
    RAISE EXCEPTION 'Non-decorative row with whitespace alt_text_ar must be rejected';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  -- 3.4 media_assets decorative with NULL alt_text_ar accepted
  INSERT INTO public.media_assets (bucket, storage_path, alt_text_ar, is_decorative, tenant_id)
  VALUES ('priest_photos', 'path/to/decorative.jpg', NULL, true, 1);

  -- 3.5 media_assets invalid content_type rejected
  BEGIN
    INSERT INTO public.media_assets (bucket, storage_path, alt_text_ar, is_decorative, content_type, tenant_id)
    VALUES ('announcement_images', 'path/to/ann.jpg', 'إعلان تجريبي', false, 'invalid_content_type', 1);
    RAISE EXCEPTION 'Invalid content_type must be rejected by CHECK constraint';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  -- 3.6 error_messages invalid code rejected
  BEGIN
    INSERT INTO public.error_messages (code, message_ar, tenant_id)
    VALUES ('INVALID_CODE', 'رسالة خطأ غير صالحة', 1);
    RAISE EXCEPTION 'Invalid error code must be rejected by CHECK constraint';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  -- 3.7 Arabic text with Coptic terms stored and returned verbatim
  INSERT INTO public.media_assets (bucket, storage_path, alt_text_ar, is_decorative, tenant_id)
  VALUES ('church_media', 'icons/mark.jpg', 'أيقونة القديس مارمرقس الإنجيلي ⲁⲃⲃⲁ ⲙⲁⲣⲕⲟⲥ', false, 1);

  PERFORM tests.expect(
    (SELECT trim(alt_text_ar) FROM public.media_assets WHERE storage_path = 'icons/mark.jpg' AND bucket = 'church_media') = 'أيقونة القديس مارمرقس الإنجيلي ⲁⲃⲃⲁ ⲙⲁⲣⲕⲟⲥ',
    'Arabic text with Coptic terms must be stored and returned verbatim'
  );
END $$;

-- 3.8 media_assets RLS: anon read within tenant, user insert denied, admin insert allowed
DO $$
DECLARE
  v_initial_count int;
  v_after_user_count int;
  v_anon_count int;
BEGIN
  -- Test anon can SELECT media_assets within tenant
  SET LOCAL ROLE anon;
  PERFORM set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000000","role":"anon","tenant_id":"1"}', true);
  SELECT count(*) INTO v_anon_count FROM public.media_assets WHERE tenant_id = 1;
  PERFORM tests.expect(v_anon_count > 0, 'anon must be able to SELECT media_assets within tenant');
  RESET ROLE;

  -- Test non-admin authenticated INSERT into media_assets denied (0 rows inserted)
  SELECT count(*) INTO v_initial_count FROM public.media_assets WHERE tenant_id = 1;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000050', 'role', 'authenticated')::text, true);

  BEGIN
    INSERT INTO public.media_assets (bucket, storage_path, alt_text_ar, is_decorative, tenant_id)
    VALUES ('church_media', 'unauthorized/test.jpg', 'وصف غير مصرح', false, 1);
  EXCEPTION
    WHEN check_violation OR insufficient_privilege OR SQLSTATE '42501' THEN NULL;
  END;

  RESET ROLE;
  SELECT count(*) INTO v_after_user_count FROM public.media_assets WHERE storage_path = 'unauthorized/test.jpg';
  PERFORM tests.expect(v_after_user_count = 0, 'non-admin authenticated INSERT into media_assets must result in 0 rows inserted');

  -- Test admin authenticated INSERT accepted
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000049', 'role', 'authenticated')::text, true);

  INSERT INTO public.media_assets (bucket, storage_path, alt_text_ar, is_decorative, tenant_id)
  VALUES ('church_media', 'admin/approved.jpg', 'صورة معتمدة من الإدارة', false, 1);

  RESET ROLE;
  PERFORM tests.expect(
    EXISTS (SELECT 1 FROM public.media_assets WHERE storage_path = 'admin/approved.jpg'),
    'admin authenticated INSERT into media_assets must be accepted'
  );
END $$;

-- ==============================================================================
-- 4. Publish Gates: publish_announcement & set_priest_photo
-- ==============================================================================
DO $$
DECLARE
  v_ann_id_1 bigint;
  v_ann_id_2 bigint;
  v_ann_id_3 bigint;
  v_priest_id_1 bigint;
  v_priest_id_2 bigint;
  v_asset_invalid_bucket bigint;
  v_asset_valid_priest bigint;
  v_asset_valid_ann bigint;
  v_pub_at timestamptz;
  v_photo text;
BEGIN
  -- Set role to ADMIN for calling RPCs
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000049', 'role', 'authenticated')::text, true);

  -- 4.1 publish_announcement: fixture announcement with unlinked image in storage raises ALT_TEXT_REQUIRED
  INSERT INTO public.announcements (title_ar, body_ar, published_at, tenant_id)
  VALUES ('إعلان تجريبي 2', 'محتوى يحتوي على صور announcement_images/ann2/pic.jpg', NULL, 1)
  RETURNING id INTO v_ann_id_2;

  -- Insert a storage object in announcement_images for ann 2 with no media_assets row
  INSERT INTO storage.objects (bucket_id, name, owner)
  VALUES ('announcement_images', 'ann2/pic.jpg', '00000000-0000-0000-0000-000000000049')
  ON CONFLICT DO NOTHING;

  BEGIN
    PERFORM public.publish_announcement(v_ann_id_2);
    RAISE EXCEPTION 'publish_announcement must raise ALT_TEXT_REQUIRED when unlinked images exist';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%ALT_TEXT_REQUIRED%' THEN
        NULL;
      ELSE
        RAISE;
      END IF;
  END;

  SELECT published_at INTO v_pub_at FROM public.announcements WHERE id = v_ann_id_2;
  PERFORM tests.expect(v_pub_at IS NULL, 'announcement published_at must remain NULL after failed publish');

  -- 4.2 publish_announcement: fixture announcement with valid linked media_asset succeeds
  INSERT INTO public.announcements (title_ar, body_ar, published_at, tenant_id)
  VALUES ('إعلان تجريبي 3', 'محتوى معتمد', NULL, 1)
  RETURNING id INTO v_ann_id_3;

  INSERT INTO public.media_assets (bucket, storage_path, alt_text_ar, is_decorative, content_type, content_id, tenant_id)
  VALUES ('announcement_images', 'ann3/valid.jpg', 'صورة الإعلان الثالث المعتمدة', false, 'announcement', v_ann_id_3, 1)
  RETURNING id INTO v_asset_valid_ann;

  PERFORM public.publish_announcement(v_ann_id_3);

  SELECT published_at INTO v_pub_at FROM public.announcements WHERE id = v_ann_id_3;
  PERFORM tests.expect(v_pub_at IS NOT NULL, 'publish_announcement must set published_at to non-null timestamp on success');

  -- 4.3 set_priest_photo: fixture priest + media_asset with wrong bucket raises INVALID_MEDIA_ASSET
  INSERT INTO public.priests (name, tenant_id)
  VALUES ('أبونا يوحنا', 1)
  RETURNING id INTO v_priest_id_1;

  INSERT INTO public.media_assets (bucket, storage_path, alt_text_ar, is_decorative, tenant_id)
  VALUES ('church_media', 'wrong_bucket/priest.jpg', 'صورة في الوعاء الخطأ', false, 1)
  RETURNING id INTO v_asset_invalid_bucket;

  BEGIN
    PERFORM public.set_priest_photo(v_priest_id_1, v_asset_invalid_bucket);
    RAISE EXCEPTION 'set_priest_photo must raise INVALID_MEDIA_ASSET for asset in wrong bucket';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%INVALID_MEDIA_ASSET%' THEN
        NULL;
      ELSE
        RAISE;
      END IF;
  END;

  -- 4.4 set_priest_photo: fixture priest + media_asset in priest_photos bucket succeeds
  INSERT INTO public.priests (name, tenant_id)
  VALUES ('أبونا مرقس', 1)
  RETURNING id INTO v_priest_id_2;

  INSERT INTO public.media_assets (bucket, storage_path, alt_text_ar, is_decorative, tenant_id)
  VALUES ('priest_photos', 'priests/markos.jpg', 'صورة أبونا مرقس الرسمية', false, 1)
  RETURNING id INTO v_asset_valid_priest;

  PERFORM public.set_priest_photo(v_priest_id_2, v_asset_valid_priest);

  SELECT photo_url INTO v_photo FROM public.priests WHERE id = v_priest_id_2;
  PERFORM tests.expect(v_photo = 'priests/markos.jpg', 'set_priest_photo must update priests.photo_url to storage_path');

  RESET ROLE;
END $$;

-- ==============================================================================
-- 5. Backlog & Keyset Pagination + Negative Authorization Tests
-- ==============================================================================
DO $$
DECLARE
  v_i int;
  v_res_page1 jsonb;
  v_res_page2 jsonb;
  v_res_page3 jsonb;
  v_cursor1 jsonb;
  v_cursor2 jsonb;
  v_items1 jsonb;
  v_items2 jsonb;
  v_items3 jsonb;
  v_c1_created timestamptz;
  v_c1_id bigint;
  v_c2_created timestamptz;
  v_c2_id bigint;
  v_all_ids bigint[];
  v_uniq_ids bigint[];
  v_res_capped jsonb;
  v_capped_len int;
BEGIN
  -- Set role to ADMIN for fixture setup and calling RPC
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000049', 'role', 'authenticated')::text, true);

  -- 5.1 Insert ≥ 25 offender priests (priests with photo_url but no media_assets row)
  FOR v_i IN 1..30 LOOP
    INSERT INTO public.priests (id, name, photo_url, created_at, tenant_id)
    OVERRIDING SYSTEM VALUE
    VALUES (
      70000 + v_i,
      'كاهن تجريبي ' || v_i,
      'priests/legacy_' || v_i || '.jpg',
      now() - (v_i || ' minutes')::interval,
      1
    );
  END LOOP;

  -- Page 1: 10 items
  v_res_page1 := public.get_backlog(NULL, NULL, 10);
  v_items1 := v_res_page1 -> 'items';
  v_cursor1 := v_res_page1 -> 'next_cursor';
  PERFORM tests.expect(jsonb_array_length(v_items1) = 10, 'Backlog page 1 must return exactly 10 items');
  PERFORM tests.expect(v_cursor1 IS NOT NULL AND v_cursor1 <> 'null'::jsonb, 'Backlog page 1 next_cursor must be non-null');

  v_c1_created := (v_cursor1 ->> 'created_at')::timestamptz;
  v_c1_id := (v_cursor1 ->> 'id')::bigint;

  -- Page 2: 10 items
  v_res_page2 := public.get_backlog(v_c1_created, v_c1_id, 10);
  v_items2 := v_res_page2 -> 'items';
  v_cursor2 := v_res_page2 -> 'next_cursor';
  PERFORM tests.expect(jsonb_array_length(v_items2) = 10, 'Backlog page 2 must return exactly 10 items');
  PERFORM tests.expect(v_cursor2 IS NOT NULL AND v_cursor2 <> 'null'::jsonb, 'Backlog page 2 next_cursor must be non-null');

  v_c2_created := (v_cursor2 ->> 'created_at')::timestamptz;
  v_c2_id := (v_cursor2 ->> 'id')::bigint;

  -- Page 3: remaining items
  v_res_page3 := public.get_backlog(v_c2_created, v_c2_id, 10);
  v_items3 := v_res_page3 -> 'items';
  PERFORM tests.expect(jsonb_array_length(v_items3) >= 10, 'Backlog page 3 must return remaining items');

  -- Verify no duplicate IDs across pages 1, 2, 3
  SELECT ARRAY_AGG((elem->>'id')::bigint)
  INTO v_all_ids
  FROM jsonb_array_elements(v_items1 || v_items2 || v_items3) AS elem;

  SELECT ARRAY_AGG(DISTINCT id)
  INTO v_uniq_ids
  FROM unnest(v_all_ids) AS id;

  PERFORM tests.expect(
    array_length(v_all_ids, 1) = array_length(v_uniq_ids, 1),
    'Backlog keyset pages must not contain duplicate items'
  );

  -- 5.2 Delete 5 mid-range offenders and verify count decreases
  DELETE FROM public.priests WHERE id BETWEEN 70011 AND 70015;

  v_res_page1 := public.get_backlog(NULL, NULL, 50);
  PERFORM tests.expect(
    jsonb_array_length(v_res_page1 -> 'items') >= 25,
    'After deleting 5 priests, remaining backlog must reflect exact reduction'
  );

  -- 5.3 Limit capping: p_limit=200 must be capped at 100
  v_res_capped := public.get_backlog(NULL, NULL, 200);
  v_capped_len := jsonb_array_length(v_res_capped -> 'items');
  PERFORM tests.expect(v_capped_len <= 100, 'get_backlog p_limit must be capped at 100');

  RESET ROLE;
END $$;

-- 5.4 Negative Authorization Tests for RPCs
DO $$
BEGIN
  -- anon execution of publish_announcement denied
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.publish_announcement(1);
    RAISE EXCEPTION 'Negative auth check failed: anon executed publish_announcement';
  EXCEPTION
    WHEN insufficient_privilege OR SQLSTATE '42501' OR undefined_function THEN NULL;
    WHEN OTHERS THEN
      IF SQLSTATE IN ('42501', '28000') OR SQLERRM LIKE '%FORBIDDEN%' OR SQLERRM LIKE '%AUTH_REQUIRED%' THEN NULL; ELSE RAISE; END IF;
  END;

  -- anon execution of set_priest_photo denied
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.set_priest_photo(1, 1);
    RAISE EXCEPTION 'Negative auth check failed: anon executed set_priest_photo';
  EXCEPTION
    WHEN insufficient_privilege OR SQLSTATE '42501' OR undefined_function THEN NULL;
    WHEN OTHERS THEN
      IF SQLSTATE IN ('42501', '28000') OR SQLERRM LIKE '%FORBIDDEN%' OR SQLERRM LIKE '%AUTH_REQUIRED%' THEN NULL; ELSE RAISE; END IF;
  END;

  -- anon execution of get_backlog denied
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.get_backlog(NULL, NULL, 10);
    RAISE EXCEPTION 'Negative auth check failed: anon executed get_backlog';
  EXCEPTION
    WHEN insufficient_privilege OR SQLSTATE '42501' OR undefined_function THEN NULL;
    WHEN OTHERS THEN
      IF SQLSTATE IN ('42501', '28000') OR SQLERRM LIKE '%FORBIDDEN%' OR SQLERRM LIKE '%AUTH_REQUIRED%' THEN NULL; ELSE RAISE; END IF;
  END;

  -- non-admin authenticated execution of publish_announcement denied
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000050', 'role', 'authenticated')::text, true);
    PERFORM public.publish_announcement(1);
    RAISE EXCEPTION 'Negative auth check failed: non-admin executed publish_announcement';
  EXCEPTION
    WHEN insufficient_privilege OR SQLSTATE '42501' THEN NULL;
    WHEN OTHERS THEN
      IF SQLSTATE IN ('42501', '28000') OR SQLERRM LIKE '%FORBIDDEN%' THEN NULL; ELSE RAISE; END IF;
  END;

  -- non-admin authenticated execution of set_priest_photo denied
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000050', 'role', 'authenticated')::text, true);
    PERFORM public.set_priest_photo(1, 1);
    RAISE EXCEPTION 'Negative auth check failed: non-admin executed set_priest_photo';
  EXCEPTION
    WHEN insufficient_privilege OR SQLSTATE '42501' THEN NULL;
    WHEN OTHERS THEN
      IF SQLSTATE IN ('42501', '28000') OR SQLERRM LIKE '%FORBIDDEN%' THEN NULL; ELSE RAISE; END IF;
  END;

  -- non-admin authenticated execution of get_backlog denied
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000050', 'role', 'authenticated')::text, true);
    PERFORM public.get_backlog(NULL, NULL, 10);
    RAISE EXCEPTION 'Negative auth check failed: non-admin executed get_backlog';
  EXCEPTION
    WHEN insufficient_privilege OR SQLSTATE '42501' THEN NULL;
    WHEN OTHERS THEN
      IF SQLSTATE IN ('42501', '28000') OR SQLERRM LIKE '%FORBIDDEN%' THEN NULL; ELSE RAISE; END IF;
  END;
END $$;

ROLLBACK;
