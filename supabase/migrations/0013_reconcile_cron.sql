-- 0013: nightly reconciliation via edge function (needs vault secrets set once)
create extension if not exists supabase_vault;

select cron.schedule('reconcile-payments', '30 3 * * *', $$
  select net.http_post(
    url := case 
      when (select decrypted_secret from vault.decrypted_secrets where name = 'SUPABASE_URL' limit 1) ~ '^https?://'
      then (select decrypted_secret from vault.decrypted_secrets where name = 'SUPABASE_URL' limit 1)
      else 'https://' || (select decrypted_secret from vault.decrypted_secrets where name = 'SUPABASE_URL' limit 1)
    end || '/functions/v1/reconcile-payments',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'SERVICE_ROLE_KEY' limit 1),
      'Content-Type', 'application/json'),
    body := '{}'
  );
$$);
