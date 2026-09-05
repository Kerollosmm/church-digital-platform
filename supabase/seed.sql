-- supabase/seed.sql: demo data for local dev. Runs automatically after
-- migrations on `supabase db reset`. Idempotent.

insert into auth.users (id, instance_id, aud, role, email, phone, encrypted_password,
                        email_confirmed_at, phone_confirmed_at,
                        confirmation_token, recovery_token, email_change_token_new, email_change,
                        reauthentication_token, phone_change, phone_change_token, email_change_token_current,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'admin@church.test', '+201000000001',
   crypt('password123', gen_salt('bf')), now(), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email","phone"]}'::jsonb, '{"name":"مدير النظام"}', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'mariam@church.test', '+201000000002',
   crypt('password123', gen_salt('bf')), now(), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email","phone"]}'::jsonb, '{"name":"مريم جورج"}', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'peter@church.test', '+201000000003',
   crypt('password123', gen_salt('bf')), now(), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email","phone"]}'::jsonb, '{"name":"بيتر عادل"}', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'priest@church.test', '+201000000004',
   crypt('password123', gen_salt('bf')), now(), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email","phone"]}'::jsonb, '{"name":"أب كيرلس"}', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'superadmin@church.local', '+201000000005',
   crypt('password123', gen_salt('bf')), now(), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email","phone"]}'::jsonb, '{"name":"مسؤول النظام العام"}', now(), now())
on conflict (id) do update set
  encrypted_password = excluded.encrypted_password,
  email_confirmed_at = excluded.email_confirmed_at,
  phone_confirmed_at = excluded.phone_confirmed_at,
  confirmation_token = excluded.confirmation_token,
  recovery_token = excluded.recovery_token,
  email_change_token_new = excluded.email_change_token_new,
  email_change = excluded.email_change,
  reauthentication_token = excluded.reauthentication_token,
  phone_change = excluded.phone_change,
  phone_change_token = excluded.phone_change_token,
  email_change_token_current = excluded.email_change_token_current,
  raw_app_meta_data = excluded.raw_app_meta_data,
  raw_user_meta_data = excluded.raw_user_meta_data;

insert into auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","email":"admin@church.test"}'::jsonb, 'email', 'aaaaaaaa-0000-0000-0000-000000000001', now(), now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', '{"sub":"aaaaaaaa-0000-0000-0000-000000000002","email":"mariam@church.test"}'::jsonb, 'email', 'aaaaaaaa-0000-0000-0000-000000000002', now(), now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000003', '{"sub":"aaaaaaaa-0000-0000-0000-000000000003","email":"peter@church.test"}'::jsonb, 'email', 'aaaaaaaa-0000-0000-0000-000000000003', now(), now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-000000000004', '{"sub":"aaaaaaaa-0000-0000-0000-000000000004","email":"priest@church.test"}'::jsonb, 'email', 'aaaaaaaa-0000-0000-0000-000000000004', now(), now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-000000000005', '{"sub":"aaaaaaaa-0000-0000-0000-000000000005","email":"superadmin@church.local"}'::jsonb, 'email', 'aaaaaaaa-0000-0000-0000-000000000005', now(), now(), now())
on conflict (provider_id, provider) do nothing;

-- handle_new_user (0002) already inserted profiles; upsert pins roles + names
insert into public.users (id, phone, name, role, tenant_id)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', '+201000000001', 'مدير النظام', 'ADMIN', 1),
  ('aaaaaaaa-0000-0000-0000-000000000002', '+201000000002', 'مريم جورج', 'USER', 1),
  ('aaaaaaaa-0000-0000-0000-000000000003', '+201000000003', 'بيتر عادل', 'USER', 1),
  ('aaaaaaaa-0000-0000-0000-000000000004', '+201000000004', 'أب كيرلس', 'ADMIN', 1),
  ('aaaaaaaa-0000-0000-0000-000000000005', '+201000000005', 'مسؤول النظام العام', 'SUPER_ADMIN', 1)
on conflict (id) do update set name = excluded.name, role = excluded.role;

do $$
begin
  if (select count(*) from public.services) = 0 then
    insert into public.services (title_ar, description, schedule, location, tenant_id)
    values ('قداس الأحد', 'القداس الأسبوعي', '{"weekly":true,"day":0,"time":"08:00"}'::jsonb, 'الكنيسة الرئيسية', 1),
           ('قداس العيد', 'قداس الأعياد السيدية', '{"special":true}'::jsonb, 'الكنيسة الرئيسية', 1);

    insert into public.service_slots (service_id, starts_at, ends_at, capacity, schedule_range, price, tenant_id)
    values ((select id from public.services where title_ar = 'قداس الأحد'),
            now() + interval '2 days', now() + interval '2 days' + interval '1 hour', 50,
            tstzrange(now() + interval '2 days', now() + interval '2 days' + interval '1 hour', '[)'), 0, 1),
           ((select id from public.services where title_ar = 'قداس الأحد'),
            now() + interval '3 days', now() + interval '3 days' + interval '1 hour', 50,
            tstzrange(now() + interval '3 days', now() + interval '3 days' + interval '1 hour', '[)'), 0, 1),
           ((select id from public.services where title_ar = 'قداس العيد'),
            now() + interval '7 days', now() + interval '7 days' + interval '2 hours', 80,
            tstzrange(now() + interval '7 days', now() + interval '7 days' + interval '2 hours', '[)'), 2000, 1);
  end if;

  if (select count(*) from public.priests) = 0 then
    insert into public.priests (name, bio, visitation_hours, tenant_id)
    values ('أب كيرلس', 'خادم الرعية', '{"tue":"18:00-20:00"}'::jsonb, 1),
           ('أب مكاري', 'خادم الرعية', '{"sat":"17:00-19:00"}'::jsonb, 1);
  end if;

  if (select count(*) from public.announcements) = 0 then
    insert into public.announcements (title_ar, body_ar, published_at, tenant_id)
    values ('اجتماع الخدام', 'الخميس الساعة 8 مساءً', now() + interval '3 days', 1);
  end if;

  if to_regclass('public.faq') is not null and not exists (select 1 from public.faq) then
    execute $faq$
      insert into public.faq (question_ar, answer_ar)
      values ('كيف أحجز قداساً؟', 'من صفحة الخدمات'),
             ('كيف أدفع؟', 'فودافون كاش أو من الكنيسة'),
             ('هل يمكن الإلغاء؟', 'نعم، قبل 24 ساعة من الموعد')
    $faq$;
  end if;

  -- Provision local vault secrets for development
  if not exists (select 1 from vault.decrypted_secrets where name = 'COMPLAINTS_KEY') then
    perform vault.create_secret('dev-complaints-encryption-key-32b', 'COMPLAINTS_KEY');
  end if;
  if not exists (select 1 from vault.decrypted_secrets where name = 'SUPABASE_URL') then
    perform vault.create_secret('http://kong:8000', 'SUPABASE_URL');
  end if;
  if not exists (select 1 from vault.decrypted_secrets where name = 'SERVICE_ROLE_KEY') then
    perform vault.create_secret('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU', 'SERVICE_ROLE_KEY');
  end if;
end $$;
