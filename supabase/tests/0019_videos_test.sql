BEGIN;

-- 0019: Decommissioned video machinery verification
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('videos', 'video_purchases')) THEN
    RAISE EXCEPTION 'FAIL: videos and video_purchases tables must be dropped';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('purchase_video', 'apply_video_payment', 'deliver_personal_video')) THEN
    RAISE EXCEPTION 'FAIL: video RPCs must be dropped';
  END IF;

  RAISE NOTICE 'OK: 0019 video decommission test passed';
END $$;

ROLLBACK;
