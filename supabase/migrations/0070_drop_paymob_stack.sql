-- 0070_drop_paymob_stack.sql
-- Feature 011 US5: Decommission and drop Paymob payment stack
-- (ADR 0003: Manual payment verification is the single rail)

-- 1. Unschedule reconcile-payments cron job
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'reconcile-payments') THEN
      PERFORM cron.unschedule('reconcile-payments');
    END IF;
  END IF;
END $$;

-- 2. Purge any PAYMOB_REFUND events from event_outbox
DELETE FROM public.event_outbox WHERE handler_type = 'PAYMOB_REFUND';

-- 3. Drop record_webhook_payment RPC
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'record_webhook_payment') THEN
    REVOKE ALL ON FUNCTION public.record_webhook_payment(text, text, int, boolean, jsonb) FROM PUBLIC, anon, authenticated, service_role;
    DROP FUNCTION public.record_webhook_payment(text, text, int, boolean, jsonb);
  END IF;
END $$;

-- 4. Drop mark_payment_failed RPC overloads
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'mark_payment_failed' AND pronargs = 2) THEN
    REVOKE ALL ON FUNCTION public.mark_payment_failed(BIGINT, jsonb) FROM PUBLIC, anon, authenticated, service_role;
    DROP FUNCTION public.mark_payment_failed(BIGINT, jsonb);
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'mark_payment_failed' AND pronargs = 1) THEN
    REVOKE ALL ON FUNCTION public.mark_payment_failed(BIGINT) FROM PUBLIC, anon, authenticated, service_role;
    DROP FUNCTION public.mark_payment_failed(BIGINT);
  END IF;
END $$;

-- 5. Drop raw_webhook column from payments table
ALTER TABLE public.payments DROP COLUMN IF EXISTS raw_webhook;
