\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;

SELECT plan(6);

-- Setup: Ensure all three secrets exist in vault for test baseline
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = 'COMPLAINTS_KEY') THEN
    PERFORM vault.create_secret('test-complaints-key', 'COMPLAINTS_KEY');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = 'SUPABASE_URL') THEN
    PERFORM vault.create_secret('http://kong:8000', 'SUPABASE_URL');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = 'SERVICE_ROLE_KEY') THEN
    PERFORM vault.create_secret('test-service-role-key', 'SERVICE_ROLE_KEY');
  END IF;
END $$;

-- Test 1: Function exists with correct signature and security properties
SELECT has_function('public', 'vault_preflight', ARRAY[]::text[], 'public.vault_preflight() exists');

-- Test 2: When all three secrets exist, vault_preflight() returns zero rows
SELECT is_empty(
  $$ SELECT * FROM public.vault_preflight() $$,
  'vault_preflight returns zero rows when all secrets present'
);

-- Test 3: When COMPLAINTS_KEY is deleted, vault_preflight() returns exactly 'COMPLAINTS_KEY'
DELETE FROM vault.secrets WHERE name = 'COMPLAINTS_KEY';
SELECT results_eq(
  $$ SELECT * FROM public.vault_preflight() $$,
  $$ VALUES ('COMPLAINTS_KEY'::text) $$,
  'vault_preflight returns COMPLAINTS_KEY when deleted'
);

-- Test 4: When all three secrets are deleted, vault_preflight() returns all three names
DELETE FROM vault.secrets WHERE name IN ('SUPABASE_URL', 'SERVICE_ROLE_KEY');
SELECT set_eq(
  $$ SELECT * FROM public.vault_preflight() $$,
  $$ VALUES ('COMPLAINTS_KEY'::text), ('SUPABASE_URL'::text), ('SERVICE_ROLE_KEY'::text) $$,
  'vault_preflight returns all missing secret names when all deleted'
);

-- Test 5: Re-create secrets and assert no secret value leaks in output
SELECT vault.create_secret('secret_val_1', 'COMPLAINTS_KEY');
SELECT vault.create_secret('secret_val_2', 'SUPABASE_URL');
-- Leave SERVICE_ROLE_KEY missing
SELECT is_empty(
  $$ SELECT * FROM public.vault_preflight() WHERE vault_preflight IN (SELECT decrypted_secret FROM vault.decrypted_secrets) $$,
  'vault_preflight output never matches any decrypted secret value'
);

-- Test 6: Security - execute revoked from authenticated
SELECT throws_ok(
  $$ SET LOCAL ROLE authenticated; SELECT * FROM public.vault_preflight(); $$,
  '42501',
  NULL,
  'authenticated role denied execute on public.vault_preflight()'
);

SELECT * FROM finish();

ROLLBACK;
