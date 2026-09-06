\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;

SELECT plan(4);

-- Test 1: Positive - admin_security_alert WHATSAPP template insert succeeds
SELECT lives_ok(
  $$ INSERT INTO public.event_outbox (tenant_id, handler_type, payload, status)
     VALUES (1, 'WHATSAPP', '{"template_name": "admin_security_alert", "phone": "+201200000001", "details": "critical security alert"}'::jsonb, 'PENDING') $$,
  'admin_security_alert WhatsApp template insert succeeds'
);

-- Test 2: Negative - invalid WhatsApp template name fails check constraint
SELECT throws_ok(
  $$ INSERT INTO public.event_outbox (tenant_id, handler_type, payload, status)
     VALUES (1, 'WHATSAPP', '{"template_name": "invalid_bogus_template", "phone": "+201200000001"}'::jsonb, 'PENDING') $$,
  '23514',
  NULL,
  'invalid WhatsApp template name rejected with check_violation'
);

-- Test 3: Positive - existing standard template (booking_confirmed) still succeeds
SELECT lives_ok(
  $$ INSERT INTO public.event_outbox (tenant_id, handler_type, payload, status)
     VALUES (1, 'WHATSAPP', '{"template_name": "booking_confirmed", "phone": "+201200000001"}'::jsonb, 'PENDING') $$,
  'standard booking_confirmed template insert still succeeds'
);

-- Test 4: Positive - non-WHATSAPP handler (e.g. FCM_PUSH) ignores template check
SELECT lives_ok(
  $$ INSERT INTO public.event_outbox (tenant_id, handler_type, payload, status)
     VALUES (1, 'FCM_PUSH', '{"custom_type": "security_push"}'::jsonb, 'PENDING') $$,
  'non-WHATSAPP handler type bypasses template name check'
);

SELECT * FROM finish();

ROLLBACK;
