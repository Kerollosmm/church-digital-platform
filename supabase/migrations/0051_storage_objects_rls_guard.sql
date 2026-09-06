-- ==============================================================================
-- Migration: 0051_storage_objects_rls_guard.sql
-- Purpose: Forward-migration counterpart to the 0044 hardening edit per AGENTS.md.
--          Ensures storage.objects RLS enable statement is safely applied on
--          existing environments. The dropped COMMENT ON statements in 0044
--          need no forward equivalent because comments are cosmetic and cannot
--          be applied without storage schema ownership.
-- ==============================================================================

DO $$
BEGIN
  ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
EXCEPTION
  WHEN insufficient_privilege THEN NULL;
END $$;
