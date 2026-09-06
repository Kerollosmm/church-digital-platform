-- 0081: offline_sync_log tenant invariant hardening
-- Closes the review finding: table lacked tenant_id and its RLS policy
-- lacked the tenant predicate; 0050 granted write DML to authenticated.

begin;

alter table public.offline_sync_log
  add column if not exists tenant_id bigint not null default public.tenant_id();

update public.offline_sync_log
  set tenant_id = public.tenant_id()
  where tenant_id is null;

drop policy if exists "Users can view own sync logs" on public.offline_sync_log;

create policy "Users can view own sync logs"
  on public.offline_sync_log
  for select
  to authenticated
  using (auth.uid() = user_id and tenant_id = public.tenant_id());

-- Revoke direct write DML granted in 0050; writes flow through
-- sync_offline_mutations RPC only.
revoke insert, update, delete on public.offline_sync_log from authenticated;

commit;
