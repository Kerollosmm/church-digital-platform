-- supabase/tests/0005_priest_self_assign_test.sql
begin;
  -- Setup test data
  insert into auth.users (id, email) values
    ('bbbbbbbb-0000-0000-0000-000000000001'::uuid, 'priest@test.com'),
    ('bbbbbbbb-0000-0000-0000-000000000002'::uuid, 'submitter@test.com');
  insert into public.users (id, name, phone, role, tenant_id) values
    ('bbbbbbbb-0000-0000-0000-000000000001'::uuid, 'Priest', '+201000000002', 'USER', 1),
    ('bbbbbbbb-0000-0000-0000-000000000002'::uuid, 'User', '+201000000003', 'USER', 1)
  on conflict (id) do nothing;

  insert into public.complaints (id, user_id, tenant_id, category, body_encrypted, status, assigned_to)
    overriding system value
    values (100, 'bbbbbbbb-0000-0000-0000-000000000002'::uuid, 1, 'GENERAL', 'encrypted_data'::bytea, 'NEW', null)
    on conflict (id) do nothing;

  -- Act as priest
  set local role authenticated;
  set local request.jwt.claims to '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}';

  -- Priest update attempt should update 0 rows or throw error due to RLS
  update public.complaints set assigned_to = 'bbbbbbbb-0000-0000-0000-000000000001'::uuid where id = 100;

  do $$
  begin
    if (select assigned_to from public.complaints where id = 100) = 'bbbbbbbb-0000-0000-0000-000000000001'::uuid then
      raise exception 'SELF-ASSIGN: priest was able to assign complaint to self';
    end if;
  end $$;
rollback;
