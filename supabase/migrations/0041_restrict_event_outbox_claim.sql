-- 0041: Restrict event outbox claim RPC to service_role only
-- Prevents anonymous and unprivileged authenticated clients from draining or locking the event outbox.

REVOKE ALL ON FUNCTION public.claim_event_outbox_batch(INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_event_outbox_batch(INT) TO service_role;

COMMENT ON FUNCTION public.claim_event_outbox_batch(INT) IS
  'Restricted to service_role only to prevent PUBLIC or unprivileged clients from draining or locking the event outbox.';
