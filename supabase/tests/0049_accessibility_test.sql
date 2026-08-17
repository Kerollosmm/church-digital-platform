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
END $$;

ROLLBACK;
