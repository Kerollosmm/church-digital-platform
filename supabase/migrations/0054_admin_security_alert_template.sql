-- Migration 0054: Add admin_security_alert template to event_outbox
-- Fixes diagnostic-engine administrative critical security alerts

ALTER TABLE public.event_outbox
  DROP CONSTRAINT IF EXISTS event_outbox_whatsapp_template_check;

ALTER TABLE public.event_outbox
  ADD CONSTRAINT event_outbox_whatsapp_template_check
  CHECK (
    handler_type <> 'WHATSAPP'
    OR (payload->>'template_name') IN (
      'booking_confirmed',
      'payment_received',
      'booking_cancelled',
      'booking_rescheduled',
      'booking_apology',
      'otp_auth',
      'booking_payment_received',
      'booking_offer',
      'admin_security_alert'
    )
  );
