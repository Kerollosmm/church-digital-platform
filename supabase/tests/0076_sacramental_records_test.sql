-- supabase/tests/0076_sacramental_records_test.sql
-- Spec 010: Sacramental Records & Family Digital Archive Test Suite

begin;
select plan(21);

-- ---------------------------------------------------------------- Fixtures
insert into auth.users (id, email, phone) values
  ('ffffffff-0000-0000-0000-000000007601'::uuid, 'user7601@test.com', '+201000007601'),
  ('ffffffff-0000-0000-0000-000000007602'::uuid, 'user7602@test.com', '+201000007602'),
  ('ffffffff-0000-0000-0000-000000007603'::uuid, 'admin7603@test.com', '+201000007603')
on conflict (id) do update set email = excluded.email, phone = excluded.phone;

insert into public.users (id, phone, name, role, tenant_id) values
  ('ffffffff-0000-0000-0000-000000007601'::uuid, '+201000007601', 'Member 76A', 'USER', 1),
  ('ffffffff-0000-0000-0000-000000007602'::uuid, '+201000007602', 'Member 76B', 'USER', 1),
  ('ffffffff-0000-0000-0000-000000007603'::uuid, '+201000007603', 'Admin 76', 'ADMIN', 1)
on conflict (id) do update set role = excluded.role;

insert into public.priests (id, name, phone, rank, tenant_id)
overriding system value
values
  (7601, 'أبونا مرقس', '+201011117601', 'HEGUMEN', 1)
on conflict (id) do update set name = excluded.name, phone = excluded.phone, rank = excluded.rank;

-- ------------------------------------------------- 1..4: Schema & Bucket Checks
select has_table('public', 'sacramental_records', 'sacramental_records table exists');
select is(
  (select relrowsecurity from pg_class where relname = 'sacramental_records'),
  true,
  'sacramental_records has RLS enabled'
);
select isnt_empty(
  $$ select 1 from storage.buckets where id = 'certificates' $$,
  'certificates storage bucket exists'
);
select is(
  (select public from storage.buckets where id = 'certificates'),
  false,
  'certificates bucket is private'
);

-- ------------------------------------------------- 5..7: Direct DML Revocations
set local role authenticated;
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007601"}';

select throws_ok(
  $$
    insert into public.sacramental_records (
      sacrament_type, recipient_name_ar, sacrament_date, tenant_id
    ) values (
      'BAPTISM', 'كيرلس ميخائيل', '2026-05-15', 1
    );
  $$,
  '42501',
  null,
  'direct insert into sacramental_records is revoked for authenticated'
);

select throws_ok(
  $$
    update public.sacramental_records set recipient_name_ar = 'Hacked';
  $$,
  '42501',
  null,
  'direct update on sacramental_records is revoked for authenticated'
);

select throws_ok(
  $$
    delete from public.sacramental_records;
  $$,
  '42501',
  null,
  'direct delete on sacramental_records is revoked for authenticated'
);
reset role;

-- ------------------------------------------------- 8..10: Issue Certificate RPC Checks
-- 8. Non-admin issuance fails with 42501
set local role authenticated;
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007601"}';

select throws_ok(
  $$
    select public.issue_sacramental_certificate(
      p_sacrament_type => 'BAPTISM',
      p_recipient_name_ar => 'كيرلس ميخائيل',
      p_sacrament_date => '2026-05-15'::date,
      p_recipient_user_id => 'ffffffff-0000-0000-0000-000000007601'::uuid
    );
  $$,
  '42501',
  null,
  'issue_sacramental_certificate rejected for non-admin'
);
reset role;

-- 9. Admin issuance with invalid sacrament type throws BAD_REQUEST (P0001)
set local role authenticated;
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007603"}';

select throws_ok(
  $$
    select public.issue_sacramental_certificate(
      p_sacrament_type => 'INVALID_SACRAMENT',
      p_recipient_name_ar => 'كيرلس ميخائيل',
      p_sacrament_date => '2026-05-15'::date
    );
  $$,
  'P0001',
  null,
  'issue_sacramental_certificate rejects invalid sacrament type'
);

-- 10. Admin issuance succeeds
select lives_ok(
  $$
    select public.issue_sacramental_certificate(
      p_sacrament_type => 'BAPTISM',
      p_recipient_name_ar => 'كيرلس ميخائيل',
      p_sacrament_date => '2026-05-15'::date,
      p_church_location_ar => 'كنيسة السيدة العذراء والأنبا بيشوي',
      p_recipient_national_id => '29901010101010',
      p_recipient_user_id => 'ffffffff-0000-0000-0000-000000007601'::uuid,
      p_officiating_priest_id => 7601,
      p_godparents_ar => 'أثناسيوس جورج',
      p_notes => 'ملاحظات سرية للكنيسة'
    );
  $$,
  'admin successfully issues baptism certificate'
);
reset role;

-- ------------------------------------------------- 11..13: RLS Isolation Checks
-- Member 1 reads own record
set local role authenticated;
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007601"}';
select is(
  (select count(*)::int from public.sacramental_records),
  1,
  'member 1 can read own sacramental record'
);

-- Member 2 cannot read member 1's record
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007602"}';
select is(
  (select count(*)::int from public.sacramental_records),
  0,
  'member 2 cannot read member 1 sacramental record'
);

-- Admin can read all records
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007603"}';
select is(
  (select count(*)::int from public.sacramental_records),
  1,
  'admin can read all sacramental records'
);
reset role;

-- ------------------------------------------------- 14..21: verify_certificate & revocation
do $$
declare
  v_token text;
  v_id uuid;
  v_res jsonb;
begin
  select id, verification_token into v_id, v_token
  from public.sacramental_records
  where recipient_user_id = 'ffffffff-0000-0000-0000-000000007601'::uuid
  limit 1;

  -- 14. anon verify_certificate
  set local role anon;
  v_res := public.verify_certificate(v_token);
  perform is((v_res ->> 'is_valid')::boolean, true, 'anon verify_certificate returns is_valid = true for valid token');

  -- 15..16. verify metadata
  perform is(v_res ->> 'recipient_name_ar', 'كيرلس ميخائيل', 'verify_certificate returns correct recipient_name_ar');
  perform is(v_res ->> 'officiating_priest_name', 'أبونا مرقس', 'verify_certificate returns officiating_priest_name');

  -- 17..18. privacy invariants
  perform is(v_res -> 'recipient_national_id', null::jsonb, 'verify_certificate strictly hides recipient_national_id');
  perform is(v_res -> 'notes', null::jsonb, 'verify_certificate strictly hides internal notes');
  reset role;

  -- 19. Non-admin revocation throws 42501
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007601"}';
  begin
    perform public.admin_revoke_certificate(v_id, 'محاولة غير مصرحة');
    perform ok(false, 'admin_revoke_certificate should fail for non-admin');
  exception when others then
    perform is(SQLSTATE, '42501', 'admin_revoke_certificate rejected for non-admin');
  end;
  reset role;

  -- 20. Admin revocation succeeds
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000007603"}';
  perform public.admin_revoke_certificate(v_id, 'إلغاء رسمي بسبب خطأ في البيانات');
  perform ok(true, 'admin_revoke_certificate succeeds for admin');
  reset role;

  -- 21. verify_certificate returns is_valid = false for revoked token
  set local role anon;
  v_res := public.verify_certificate(v_token);
  perform is((v_res ->> 'is_valid')::boolean, false, 'verify_certificate returns is_valid = false after revocation');
  reset role;
end $$;

rollback;
