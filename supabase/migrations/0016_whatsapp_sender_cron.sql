-- 0016: event-dispatcher pg_cron job (every minute drain)
create extension if not exists supabase_vault;

select cron.schedule('event-dispatcher', '* * * * *', $$
  select net.http_post(
    url := 'https://' || (select decrypted_secret from vault.decrypted_secrets where name = 'SUPABASE_URL' limit 1)
       || '/functions/v1/event-dispatcher',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'SERVICE_ROLE_KEY' limit 1),
      'Content-Type', 'application/json'),
    body := '{}');
$$);
