-- 0055_vault_preflight.sql
-- Preflight check returning missing vault secrets required by backend subsystems

create or replace function public.vault_preflight()
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select required_secret
  from (values ('COMPLAINTS_KEY'), ('SUPABASE_URL'), ('SERVICE_ROLE_KEY')) as req(required_secret)
  where not exists (
    select 1
    from vault.decrypted_secrets s
    where s.name = req.required_secret
  );
$$;

revoke all on function public.vault_preflight() from public, anon, authenticated;
grant execute on function public.vault_preflight() to service_role;
