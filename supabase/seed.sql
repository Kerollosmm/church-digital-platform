-- supabase/seed.sql: demo data for local dev. Runs automatically after
-- migrations on `supabase db reset`. Idempotent.

insert into auth.users (id, instance_id, aud, role, email, phone,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'admin@church.test', '+201000000001',
   '{}', '{"name":"مدير النظام"}', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'mariam@church.test', '+201000000002',
   '{}', '{"name":"مريم جورج"}', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000003',
   'authenticated', 'authenticated', 'peter@church.test', '+201000000003',
   '{}', '{"name":"بيتر عادل"}', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'priest@church.test', '+201000000004',
   '{}', '{"name":"أب كيرلس"}', now(), now())
on conflict (id) do nothing;

-- handle_new_user (0002) already inserted profiles; upsert pins roles + names
insert into public.users (id, phone, name, role, tenant_id)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', '+201000000001', 'مدير النظام', 'ADMIN', 1),
  ('aaaaaaaa-0000-0000-0000-000000000002', '+201000000002', 'مريم جورج', 'USER', 1),
  ('aaaaaaaa-0000-0000-0000-000000000003', '+201000000003', 'بيتر عادل', 'USER', 1),
  ('aaaaaaaa-0000-0000-0000-000000000004', '+201000000004', 'أب كيرلس', 'ADMIN', 1)
on conflict (id) do update set name = excluded.name, role = excluded.role;

do $$
begin
  if (select count(*) from public.services) = 0 then
    insert into public.services (title_ar, description, schedule, location, tenant_id)
    values ('قداس الأحد', 'القداس الأسبوعي', '{"weekly":true,"day":0,"time":"08:00"}'::jsonb, 'الكنيسة الرئيسية', 1),
           ('قداس العيد', 'قداس الأعياد السيدية', '{"special":true}'::jsonb, 'الكنيسة الرئيسية', 1);

    insert into public.service_slots (service_id, starts_at, ends_at, capacity, remaining_capacity, schedule_range, price, tenant_id)
    values ((select id from public.services where title_ar = 'قداس الأحد'),
            now() + interval '2 days', now() + interval '2 days' + interval '1 hour', 50, 50,
            tstzrange(now() + interval '2 days', now() + interval '2 days' + interval '1 hour', '[)'), 0, 1),
           ((select id from public.services where title_ar = 'قداس الأحد'),
            now() + interval '3 days', now() + interval '3 days' + interval '1 hour', 50, 50,
            tstzrange(now() + interval '3 days', now() + interval '3 days' + interval '1 hour', '[)'), 0, 1),
           ((select id from public.services where title_ar = 'قداس العيد'),
            now() + interval '7 days', now() + interval '7 days' + interval '2 hours', 80, 80,
            tstzrange(now() + interval '7 days', now() + interval '7 days' + interval '2 hours', '[)'), 20, 1);
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
end $$;
