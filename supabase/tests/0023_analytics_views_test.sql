-- supabase/tests/0023_analytics_views_test.sql
DO $$
DECLARE n int;
BEGIN
  PERFORM public.materialize_analytics();
  SET ROLE anon;
  IF EXISTS (SELECT 1 FROM public.v_analytics_utilization) THEN
    RAISE EXCEPTION 'FAIL: anon sees analytics';
  END IF;
  RESET ROLE;
  SET ROLE authenticated;
  SELECT count(*) INTO n FROM public.v_analytics_utilization;
  IF n != 0 THEN RAISE EXCEPTION 'FAIL: non-admin sees analytics'; END IF;
  RESET ROLE;
  RAISE NOTICE 'PASS: analytics RLS';
END $$;
