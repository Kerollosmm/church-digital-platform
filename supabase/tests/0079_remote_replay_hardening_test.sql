BEGIN;
SELECT plan(4);

-- 1. Verify search_cashier_bookings function exists
SELECT has_function(
  'public',
  'search_cashier_bookings',
  ARRAY['text', 'text', 'integer', 'integer'],
  'search_cashier_bookings RPC exists'
);

-- 2. Verify EXECUTE is granted to authenticated
SELECT function_privs_are(
  'public',
  'search_cashier_bookings',
  ARRAY['text', 'text', 'integer', 'integer'],
  'authenticated',
  ARRAY['EXECUTE'],
  'authenticated has EXECUTE privilege on search_cashier_bookings'
);

-- 3. Verify EXECUTE is revoked from anon
SELECT function_privs_are(
  'public',
  'search_cashier_bookings',
  ARRAY['text', 'text', 'integer', 'integer'],
  'anon',
  ARRAY[]::text[],
  'anon has NO EXECUTE privilege on search_cashier_bookings'
);

-- 4. Verify index on event_bookings exists
SELECT has_index(
  'public',
  'event_bookings',
  'idx_event_bookings_customer_search',
  'idx_event_bookings_customer_search index exists'
);

SELECT * FROM finish();
ROLLBACK;
