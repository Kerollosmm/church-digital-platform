-- Prod-only drift cleanup: an out-of-band trigger on payments referenced
-- payment_audit_logs columns that no longer exist after 0073, breaking any
-- write to payments (including the 0083 piastres backfill).
begin;

drop trigger if exists trg_log_payment_change on public.payments;
drop function if exists public.log_payment_change();

commit;
