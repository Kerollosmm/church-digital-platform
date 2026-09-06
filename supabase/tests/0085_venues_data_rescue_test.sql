BEGIN;
SELECT plan(3);

-- 0085 rescue: inserts from drift venues are a no-op locally (table absent),
-- so venues_resources stays exactly as the seed left it.
SELECT has_table('public', 'venues_resources', 'venues_resources intact after rescue migration');
SELECT is(
  (SELECT count(*) FROM public.venues_resources WHERE deleted_at IS NULL),
  (SELECT count(*) FROM public.venues_resources),
  'no soft-deleted venue rows introduced by rescue'
);
SELECT is(
  (SELECT count(*) FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'venues'),
  0::bigint,
  'drift venues table absent locally (rescue insert path is no-op)'
);

SELECT * FROM finish();
ROLLBACK;
