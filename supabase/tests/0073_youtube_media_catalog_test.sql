-- 0073_youtube_media_catalog_test.sql
-- Verifies the youtube_videos catalog: table + RLS, public read view,
-- the sync_youtube_videos RPC upsert/mark-unavailable behaviour, and that
-- the RPC is revoked from anon/authenticated.

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  v_admin_id uuid := '00000000-0000-0000-0000-000000000073';
  v_user_id  uuid := '00000000-0000-0000-0000-000000000174';
  v_count   int;
  v_result  jsonb;
BEGIN
  -- 0. Seed test users
  INSERT INTO auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES
    (v_admin_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a073@test.local', '+201099990073', '{}', '{}', now(), now()),
    (v_user_id,  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'u073@test.local', '+201099990074', '{}', '{}', now(), now())
  ON CONFLICT (id) DO NOTHING;
  UPDATE public.users SET role = 'ADMIN', tenant_id = 1, deleted_at = null WHERE id = v_admin_id;
  UPDATE public.users SET role = 'USER',  tenant_id = 1, deleted_at = null WHERE id = v_user_id;

  -- 1. Table exists with RLS enabled
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='youtube_videos') THEN
    RAISE EXCEPTION 'FAIL: youtube_videos table missing';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE relname='youtube_videos') THEN
    RAISE EXCEPTION 'FAIL: youtube_videos RLS not enabled';
  END IF;

  -- 2. sync_youtube_videos upserts a batch (runs as service_role/superuser)
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id, 'role', 'authenticated', 'tenant_id', 1)::text, true);
  v_result := public.sync_youtube_videos('UCtestchannel', jsonb_build_array(
    jsonb_build_object('yt_video_id','vidA','title','Mass','description','d','thumbnail_url','t1','yt_url','https://www.youtube.com/watch?v=vidA','published_at','2026-08-20T10:00:00Z','duration_seconds',3600),
    jsonb_build_object('yt_video_id','vidB','title','Sermon','description','d2','thumbnail_url','t2','yt_url','https://www.youtube.com/watch?v=vidB','published_at','2026-08-13T10:00:00Z','duration_seconds',2700)
  ));
  IF (v_result->>'upserted')::int <> 2 THEN
    RAISE EXCEPTION 'FAIL: expected 2 upserts, got %', v_result;
  END IF;

  SELECT count(*) INTO v_count FROM public.youtube_videos WHERE tenant_id = 1;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FAIL: expected 2 catalog rows, got %', v_count;
  END IF;

  -- 3. Second sync upserts (no dup) and marks a now-missing video unavailable
  v_result := public.sync_youtube_videos('UCtestchannel', jsonb_build_array(
    jsonb_build_object('yt_video_id','vidA','title','Mass v2','description','d','thumbnail_url','t1','yt_url','https://www.youtube.com/watch?v=vidA','published_at','2026-08-20T10:00:00Z','duration_seconds',3600)
  ));
  IF (v_result->>'upserted')::int <> 1 THEN
    RAISE EXCEPTION 'FAIL: expected 1 upsert on second sync, got %', v_result;
  END IF;
  -- vidB should now be unavailable, vidA available + title updated
  SELECT count(*) INTO v_count FROM public.youtube_videos WHERE yt_video_id='vidB' AND is_available = false;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: missing video should be marked unavailable';
  END IF;
  SELECT count(*) INTO v_count FROM public.youtube_videos WHERE yt_video_id='vidA' AND is_available = true AND title='Mass v2';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: upserted video should be available with updated title';
  END IF;

  -- 4. Anonymous can read available rows only via the view
  SET LOCAL ROLE anon;
  SELECT count(*) INTO v_count FROM public.v_sermons;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: anon should see 1 available sermon via v_sermons, got %', v_count;
  END IF;
  -- anon cannot insert directly
  BEGIN
    INSERT INTO public.youtube_videos (yt_video_id, title, yt_url, tenant_id) VALUES ('vidX','x','https://www.youtube.com/watch?v=vidX',1);
    RAISE EXCEPTION 'FAIL: anon must NOT insert youtube_videos';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FAIL: anon must NOT insert%' THEN RAISE; END IF;
  END;

  -- anon cannot execute the privileged sync RPC (revoked from anon/authenticated)
  BEGIN
    PERFORM public.sync_youtube_videos('UCtestchannel', '[]'::jsonb);
    RAISE EXCEPTION 'FAIL: anon must NOT execute sync_youtube_videos';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FAIL: anon must NOT execute%' THEN RAISE; END IF;
  END;

  -- 5. Regular USER can read but cannot insert
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_id, 'role', 'authenticated', 'tenant_id', 1)::text, true);
  SELECT count(*) INTO v_count FROM public.v_sermons;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: user should see 1 available sermon, got %', v_count;
  END IF;
  BEGIN
    INSERT INTO public.youtube_videos (yt_video_id, title, yt_url, tenant_id) VALUES ('vidY','y','https://www.youtube.com/watch?v=vidY',1);
    RAISE EXCEPTION 'FAIL: regular USER must NOT insert youtube_videos';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FAIL: regular USER must NOT insert%' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'OK: 0073 youtube media catalog test passed';
END $$;

ROLLBACK;
