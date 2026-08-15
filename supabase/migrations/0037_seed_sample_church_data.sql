-- 0037_seed_sample_church_data.sql
-- Seed sample services, clergy directory, and future mass/retreat slots

-- 1. Seed Core Services
insert into public.services (title_ar, description, schedule, location, tenant_id)
values 
  ('القداس الإلهي', 'حجز حضور وتناول الأسرار المقدسة في القداسات الإلهية', '{"days": ["Friday", "Sunday"]}'::jsonb, 'الكنيسة الرئيسية', 1),
  ('سر الاعتراف', 'حجز مواعيد الاعتراف والإرشاد الروحي مع الآباء الكهنة', '{"days": ["Wednesday", "Saturday"]}'::jsonb, 'غرف الاعترافات', 1),
  ('المصايف والرحلات', 'أفواج المصايف الكنسية والخلوات الروحية السنوية', '{"season": "Summer"}'::jsonb, 'بيوت المؤتمرات', 1)
on conflict do nothing;

-- 2. Seed Priests Directory
insert into public.priests (name, photo_url, bio, visitation_hours, tenant_id)
values
  ('القمص بيشوي كامل', 'https://images.unsplash.com/photo-1544005313-94ddf0286df2', 'كاهن كنيسة الشهيد مارجرجس، مسؤول خدمة الشباب والافتقاد', '{"available": "الجمعة والأحد بعد القداس"}'::jsonb, 1),
  ('القس بولس جورج', 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d', 'كاهن كنيسة القديس مرقس، مسؤول المشورة الأسرية والإرشاد الروحي', '{"available": "السبت والأربعاء مساءً"}'::jsonb, 1),
  ('القس داود لمعي', 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e', 'كاهن كنيسة مارمرقس، مسؤول خدمة الكرازة والتعليم اللاهوتي', '{"available": "الخميس والجمعة"}'::jsonb, 1)
on conflict do nothing;

-- 3. Seed Service Slots (Holy Masses & Retreats)
do $$
declare
  v_liturgy_id bigint;
  v_confession_id bigint;
  v_retreat_id bigint;
begin
  select id into v_liturgy_id from public.services where title_ar = 'القداس الإلهي' limit 1;
  select id into v_confession_id from public.services where title_ar = 'سر الاعتراف' limit 1;
  select id into v_retreat_id from public.services where title_ar = 'المصايف والرحلات' limit 1;

  -- Masses (Free)
  insert into public.service_slots (
    service_id, starts_at, ends_at, capacity, remaining_capacity, price, status, location, schedule_range, tenant_id
  ) values
    (
      v_liturgy_id,
      date_trunc('day', now() + interval '1 day') + interval '6 hours 30 minutes',
      date_trunc('day', now() + interval '1 day') + interval '9 hours 30 minutes',
      150, 150, 0, 'OPEN', 'مذبح الشهيد مارجرجس - الكاتدرائية',
      tstzrange(date_trunc('day', now() + interval '1 day') + interval '6 hours 30 minutes', date_trunc('day', now() + interval '1 day') + interval '9 hours 30 minutes', '[)'),
      1
    ),
    (
      v_liturgy_id,
      date_trunc('day', now() + interval '2 days') + interval '7 hours',
      date_trunc('day', now() + interval '2 days') + interval '9 hours 30 minutes',
      100, 100, 0, 'OPEN', 'مذبح القديسة دميانة - الكنيسة الصغرى',
      tstzrange(date_trunc('day', now() + interval '2 days') + interval '7 hours', date_trunc('day', now() + interval '2 days') + interval '9 hours 30 minutes', '[)'),
      1
    ),
    (
      v_liturgy_id,
      date_trunc('day', now() + interval '3 days') + interval '6 hours',
      date_trunc('day', now() + interval '3 days') + interval '8 hours 30 minutes',
      200, 200, 0, 'OPEN', 'مذبح الملاك ميخائيل - الطابق الأرضي',
      tstzrange(date_trunc('day', now() + interval '3 days') + interval '6 hours', date_trunc('day', now() + interval '3 days') + interval '8 hours 30 minutes', '[)'),
      1
    ),

    -- Retreats & Trips (Paid)
    (
      v_retreat_id,
      date_trunc('day', now() + interval '10 days') + interval '8 hours',
      date_trunc('day', now() + interval '15 days') + interval '18 hours',
      60, 60, 1500, 'OPEN', 'بيت مارمرقس للمؤتمرات - مرسى مطروح',
      tstzrange(date_trunc('day', now() + interval '10 days') + interval '8 hours', date_trunc('day', now() + interval '15 days') + interval '18 hours', '[)'),
      1
    ),
    (
      v_retreat_id,
      date_trunc('day', now() + interval '18 days') + interval '9 hours',
      date_trunc('day', now() + interval '20 days') + interval '17 hours',
      40, 40, 450, 'OPEN', 'دير القديس أنبا بيشوي - وادي النطرون',
      tstzrange(date_trunc('day', now() + interval '18 days') + interval '9 hours', date_trunc('day', now() + interval '20 days') + interval '17 hours', '[)'),
      1
    ),

    -- Confession Slots
    (
      v_confession_id,
      date_trunc('day', now() + interval '1 day') + interval '17 hours',
      date_trunc('day', now() + interval '1 day') + interval '19 hours',
      10, 10, 0, 'OPEN', 'غرفة الإرشاد والمشورة 1',
      tstzrange(date_trunc('day', now() + interval '1 day') + interval '17 hours', date_trunc('day', now() + interval '1 day') + interval '19 hours', '[)'),
      1
    ),
    (
      v_confession_id,
      date_trunc('day', now() + interval '2 days') + interval '18 hours',
      date_trunc('day', now() + interval '2 days') + interval '20 hours',
      8, 8, 0, 'OPEN', 'غرفة الاعتراف - الدور الأول',
      tstzrange(date_trunc('day', now() + interval '2 days') + interval '18 hours', date_trunc('day', now() + interval '2 days') + interval '20 hours', '[)'),
      1
    )
  on conflict do nothing;
end;
$$;
