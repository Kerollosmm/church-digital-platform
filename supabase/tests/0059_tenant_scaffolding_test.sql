\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;

SELECT plan(8);

-- 1. payments_monthly primary key is (tenant_id, month)
SELECT col_is_pk(
  'public',
  'payments_monthly',
  ARRAY['tenant_id', 'month'],
  'payments_monthly primary key is (tenant_id, month)'
);

-- 2. whatsapp_optins primary key is (tenant_id, phone)
SELECT col_is_pk(
  'public',
  'whatsapp_optins',
  ARRAY['tenant_id', 'phone'],
  'whatsapp_optins primary key is (tenant_id, phone)'
);

-- 3. audit_log has column tenant_id with default tenant_id() and not null
SELECT col_not_null(
  'public',
  'audit_log',
  'tenant_id',
  'audit_log.tenant_id is NOT NULL'
);

SELECT col_has_default(
  'public',
  'audit_log',
  'tenant_id',
  'audit_log.tenant_id has default'
);

-- 4. whatsapp_optins.tenant_id is NOT NULL and has default
SELECT col_not_null(
  'public',
  'whatsapp_optins',
  'tenant_id',
  'whatsapp_optins.tenant_id is NOT NULL'
);

SELECT col_has_default(
  'public',
  'whatsapp_optins',
  'tenant_id',
  'whatsapp_optins.tenant_id has default'
);

-- 5. whatsapp_optins accepts duplicate phone across different tenant_id
SELECT lives_ok(
  $$
  INSERT INTO public.whatsapp_optins (tenant_id, phone, source) VALUES
    (1, '+201099887766', 'BOOKING'),
    (2, '+201099887766', 'BOOKING')
  $$,
  'whatsapp_optins accepts duplicate phone across different tenant_id'
);

-- 6. materialize_analytics populates payments_monthly for multiple tenants
DO $$
DECLARE
  v_count integer;
BEGIN
  -- Insert payments for two tenants
  INSERT INTO public.payments (tenant_id, amount, status) VALUES
    (1, 500, 'PAID'),
    (2, 750, 'PAID');

  PERFORM public.materialize_analytics();

  SELECT count(*)::integer INTO v_count
  FROM public.payments_monthly
  WHERE month = (date_trunc('month', now() AT TIME ZONE 'Africa/Cairo'))::date
    AND tenant_id IN (1, 2);

  PERFORM ok(v_count >= 2, 'materialize_analytics creates distinct payments_monthly rows for each tenant_id');
END $$;

SELECT * FROM finish();

ROLLBACK;
