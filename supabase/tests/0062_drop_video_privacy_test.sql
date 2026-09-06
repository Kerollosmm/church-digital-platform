\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;

SELECT plan(1);

-- 1. video_privacy enum type does not exist
SELECT is(
  (SELECT count(*)::integer FROM pg_type WHERE typname = 'video_privacy'),
  0,
  'orphan video_privacy enum type must be dropped'
);

SELECT * FROM finish();

ROLLBACK;
