-- ==============================================================================
-- supabase/tests/0077_sunday_school_management_test.sql
-- Spec 011: Servants & Sunday School Management Test Suite
-- ==============================================================================

begin;
select plan(22);

-- ---------------------------------------------------------------- Fixtures
insert into auth.users (id, email, phone) values
  ('ffffffff-0000-0000-0000-000000007701'::uuid, 'member7701@test.com', '+201000007701'),
  ('ffffffff-0000-0000-0000-000000007702'::uuid, 'servant7702@test.com', '+201000007702'),
  ('ffffffff-0000-0000-0000-000000007703'::uuid, 'admin7703@test.com', '+201000007703'),
  ('ffffffff-0000-0000-0000-000000007704'::uuid, 'other_servant7704@test.com', '+201000007704')
on conflict (id) do update set email = excluded.email, phone = excluded.phone;

insert into public.users (id, phone, name, role, tenant_id) values
  ('ffffffff-0000-0000-0000-000000007701'::uuid, '+201000007701', 'Member 77', 'USER', 1),
  ('ffffffff-0000-0000-0000-000000007702'::uuid, '+201000007702', 'Servant Mark', 'USER', 1),
  ('ffffffff-0000-0000-0000-000000007703'::uuid, '+201000007703', 'Admin Mina', 'ADMIN', 1),
  ('ffffffff-0000-0000-0000-000000007704'::uuid, '+201000007704', 'Other Servant George', 'USER', 1)
on conflict (id) do update set role = excluded.role;

-- ------------------------------------------------- 1..5: Table Existence & RLS Checks
select has_table('public', 'sunday_school_classes', 'sunday_school_classes table exists');
select has_table('public', 'sunday_school_servants', 'sunday_school_servants table exists');
select has_table('public', 'sunday_school_students', 'sunday_school_students table exists');
select has_table('public', 'sunday_school_sessions', 'sunday_school_sessions table exists');
select has_table('public', 'sunday_school_attendance', 'sunday_school_attendance table exists');

-- ------------------------------------------------- 6..9: Setup Class, Servants, Students
insert into public.sunday_school_classes (id, name_ar, stage, grade_level, academic_year, tenant_id)
values
  ('11111111-7701-0000-0000-000000000001'::uuid, 'فصل داود النبي - رابعة ابتدائي', 'PRIMARY', 4, '2025-2026', 1),
  ('11111111-7702-0000-0000-000000000002'::uuid, 'فصل مارمرقس - أولى إعدادي', 'PREPARATORY', 1, '2025-2026', 1)
on conflict (id) do nothing;

select is(
  (select count(*)::int from public.sunday_school_classes where academic_year = '2025-2026'),
  2,
  'sunday school classes created successfully'
);

-- Servant Assignment
insert into public.sunday_school_servants (id, class_id, user_id, role, is_active, tenant_id)
values
  ('22222222-7701-0000-0000-000000000001'::uuid, '11111111-7701-0000-0000-000000000001'::uuid, 'ffffffff-0000-0000-0000-000000007702'::uuid, 'LEADER', true, 1),
  ('22222222-7702-0000-0000-000000000002'::uuid, '11111111-7702-0000-0000-000000000002'::uuid, 'ffffffff-0000-0000-0000-000000007704'::uuid, 'SERVANT', true, 1)
on conflict (id) do nothing;

select is(
  (select count(*)::int from public.sunday_school_servants where class_id = '11111111-7701-0000-0000-000000000001'::uuid),
  1,
  'servant assigned to class 1'
);

-- Student Enrollment
insert into public.sunday_school_students (id, class_id, full_name_ar, birth_date, parent_phone, tenant_id)
values
  ('33333333-7701-0000-0000-000000000001'::uuid, '11111111-7701-0000-0000-000000000001'::uuid, 'كيرلس مينا', '2015-05-10', '+201011112222', 1),
  ('33333333-7702-0000-0000-000000000002'::uuid, '11111111-7701-0000-0000-000000000001'::uuid, 'يوسف سامح', '2015-08-20', '+201033334444', 1),
  ('33333333-7703-0000-0000-000000000003'::uuid, '11111111-7702-0000-0000-000000000002'::uuid, 'جورج أمير', '2012-03-15', '+201055556666', 1)
on conflict (id) do nothing;

select is(
  (select count(*)::int from public.sunday_school_students where class_id = '11111111-7701-0000-0000-000000000001'::uuid),
  2,
  'students enrolled in class 1'
);

-- Duplicate servant assignment fails
select throws_ok(
  $$
    insert into public.sunday_school_servants (class_id, user_id, role, tenant_id)
    values ('11111111-7701-0000-0000-000000000001'::uuid, 'ffffffff-0000-0000-0000-000000007702'::uuid, 'ASSISTANT', 1);
  $$,
  '23505',
  null,
  'duplicate servant assignment to same class throws unique violation 23505'
);

-- ------------------------------------------------- 10..12: Direct DML Revocation Checks
set local role authenticated;
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007702"}';

select throws_ok(
  $$
    insert into public.sunday_school_attendance (class_id, student_id, session_date, status, tenant_id)
    values ('11111111-7701-0000-0000-000000000001'::uuid, '33333333-7701-0000-0000-000000000001'::uuid, '2026-08-23', 'PRESENT', 1);
  $$,
  '42501',
  null,
  'direct insert into sunday_school_attendance is revoked for authenticated users'
);

select throws_ok(
  $$
    insert into public.sunday_school_classes (name_ar, stage, tenant_id)
    values ('فصل جديد', 'PRIMARY', 1);
  $$,
  '42501',
  null,
  'direct insert into sunday_school_classes is revoked for authenticated non-admin'
);

-- ------------------------------------------------- 12..14: Helper Function is_class_servant
select is(
  public.is_class_servant('11111111-7701-0000-0000-000000000001'::uuid),
  true,
  'servant 7702 is identified as servant of class 1'
);

select is(
  public.is_class_servant('11111111-7702-0000-0000-000000000002'::uuid),
  false,
  'servant 7702 is NOT servant of class 2'
);

-- ------------------------------------------------- 14..18: Attendance Recording Security & Edge Cases
-- 1. Unauthorized non-servant call fails (Member 7701)
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007701"}';

select throws_ok(
  $$
    select public.record_bulk_attendance(
      '11111111-7701-0000-0000-000000000001'::uuid,
      '2026-08-23'::date,
      jsonb_build_array(
        jsonb_build_object('student_id', '33333333-7701-0000-0000-000000000001'::uuid, 'status', 'PRESENT')
      ),
      'درس المحبة والأمانة'
    );
  $$,
  '42501',
  null,
  'unauthorized non-servant member cannot record attendance (throws FORBIDDEN 42501)'
);

-- 2. Other servant not assigned to Class 1 fails
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007704"}';

select throws_ok(
  $$
    select public.record_bulk_attendance(
      '11111111-7701-0000-0000-000000000001'::uuid,
      '2026-08-23'::date,
      jsonb_build_array(
        jsonb_build_object('student_id', '33333333-7701-0000-0000-000000000001'::uuid, 'status', 'PRESENT')
      ),
      'درس الصدق'
    );
  $$,
  '42501',
  null,
  'unassigned servant cannot record attendance for class 1 (throws FORBIDDEN 42501)'
);

-- 3. Assigned Servant 7702 records attendance successfully
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007702"}';

select lives_ok(
  $$
    select public.record_bulk_attendance(
      '11111111-7701-0000-0000-000000000001'::uuid,
      '2026-08-23'::date,
      jsonb_build_array(
        jsonb_build_object('student_id', '33333333-7701-0000-0000-000000000001'::uuid, 'status', 'PRESENT', 'notes', 'حاضر في الموعد'),
        jsonb_build_object('student_id', '33333333-7702-0000-0000-000000000002'::uuid, 'status', 'ABSENT', 'notes', 'مسافر مع الأسرة')
      ),
      'درس الأمانة والفضيلة'
    );
  $$,
  'assigned servant successfully records bulk attendance'
);

select is(
  (select count(*)::int from public.sunday_school_attendance where class_id = '11111111-7701-0000-0000-000000000001'::uuid and session_date = '2026-08-23'::date),
  2,
  'two attendance records persisted'
);

select is(
  (select topic_title_ar from public.sunday_school_sessions where class_id = '11111111-7701-0000-0000-000000000001'::uuid and session_date = '2026-08-23'::date),
  'درس الأمانة والفضيلة',
  'session topic recorded correctly'
);

-- 4. Cross-class student submission fails
select throws_ok(
  $$
    select public.record_bulk_attendance(
      '11111111-7701-0000-0000-000000000001'::uuid,
      '2026-08-23'::date,
      jsonb_build_array(
        jsonb_build_object('student_id', '33333333-7703-0000-0000-000000000003'::uuid, 'status', 'PRESENT')
      )
    );
  $$,
  'P0001',
  null,
  'student not belonging to class is rejected with STUDENT_NOT_IN_CLASS'
);

-- 5. Duplicate attendance update (upsert) on same date succeeds and updates status
select lives_ok(
  $$
    select public.record_bulk_attendance(
      '11111111-7701-0000-0000-000000000001'::uuid,
      '2026-08-23'::date,
      jsonb_build_array(
        jsonb_build_object('student_id', '33333333-7702-0000-0000-000000000002'::uuid, 'status', 'EXCUSED', 'notes', 'اعتذار رسمي')
      ),
      'تحديث حالة الغياب'
    );
  $$,
  'upserting attendance for existing session date updates status smoothly'
);

select is(
  (select status from public.sunday_school_attendance where student_id = '33333333-7702-0000-0000-000000000002'::uuid and session_date = '2026-08-23'::date),
  'EXCUSED',
  'student status updated to EXCUSED via upsert'
);

-- 6. Admin can also record attendance for any class
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007703"}';

select lives_ok(
  $$
    select public.record_bulk_attendance(
      '11111111-7702-0000-0000-000000000002'::uuid,
      '2026-08-23'::date,
      jsonb_build_array(
        jsonb_build_object('student_id', '33333333-7703-0000-0000-000000000003'::uuid, 'status', 'PRESENT', 'notes', 'حضور ممتاز')
      ),
      'درس القيامة'
    );
  $$,
  'admin can record attendance for any class'
);

reset role;
rollback;
