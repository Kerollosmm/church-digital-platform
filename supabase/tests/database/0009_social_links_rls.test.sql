-- pgTAP test: 0009_social_links_rls.test.sql
BEGIN;
SELECT plan(7);

-- 1. Table exists
SELECT has_table('public', 'social_links', 'Table public.social_links exists');

-- 2. RLS enabled
SELECT table_privs_are(
  'public', 'social_links', 'anon', ARRAY['SELECT'],
  'anon role has only SELECT privilege on social_links'
);

-- 3. Required columns exist
SELECT columns_are(
  'public', 'social_links',
  ARRAY['id', 'platform', 'title_ar', 'url', 'icon_name', 'position', 'is_active', 'tenant_id', 'created_at', 'updated_at', 'deleted_at'],
  'social_links has exact expected columns'
);

-- 4. Primary key is bigint id
SELECT col_type_is('public', 'social_links', 'id', 'bigint', 'social_links.id is bigint');

-- 5. Policies exist
SELECT policies_are(
  'public', 'social_links',
  ARRAY['social_links public read', 'social_links admin all'],
  'social_links has expected public read and admin all policies'
);

-- 6. Check policy count
SELECT is(
  (SELECT count(*)::int FROM pg_policies WHERE schemaname = 'public' AND tablename = 'social_links'),
  2,
  'social_links has exactly 2 RLS policies'
);

-- 7. Check sequence privileges for authenticated role
SELECT is(
  has_sequence_privilege('authenticated', pg_get_serial_sequence('public.social_links', 'id'), 'USAGE'),
  true,
  'authenticated role has USAGE privilege on social_links identity sequence'
);

SELECT * FROM finish();
ROLLBACK;
