-- 0020: daily expiry sweep (each videos.update call = 50 quota units)
select cron.schedule('youtube-expiry', '0 4 * * *', $$
  select net.http_post(
    url := 'https://' || (select decrypted_secret from vault.decrypted_secrets where name = 'SUPABASE_URL' limit 1)
       || '/functions/v1/youtube-expiry',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'SERVICE_ROLE_KEY' limit 1),
      'Content-Type', 'application/json'),
    body := '{}'
  );
$$);
