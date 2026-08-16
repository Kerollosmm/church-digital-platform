-- 0026: complaints pgp round-trip + access rules + view metadata read isolation
do $$
declare
  v_u uuid := '00000000-0000-0000-0000-000000000021';
  v_other uuid := '00000000-0000-0000-0000-000000000022';
  v_a uuid := '00000000-0000-0000-0000-000000000023';
  v_cid bigint;
  v_body text;
  v_enc bytea;
  v_cnt int;
  v_cat text;
  v_stat text;
begin
  insert into auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values (v_u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c1@test.local', '+201022222221', '{}', '{}', now(), now()),
         (v_other, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c2@test.local', '+201022222222', '{}', '{}', now(), now()),
         (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c3@test.local', '+201022222223', '{}', '{}', now(), now())
  on conflict (id) do nothing;
  update public.users set role = 'USER', tenant_id = 1, deleted_at = null where id in (v_u, v_other);
  update public.users set role = 'ADMIN', tenant_id = 1, deleted_at = null where id = v_a;

  -- vault key (test-scoped; dev key ships in seed — see Step 2)
  if not exists (select 1 from vault.decrypted_secrets where name = 'COMPLAINTS_KEY') then
    perform vault.create_secret('test-complaints-key', 'COMPLAINTS_KEY');
  end if;

  -- 1. Submitter submits complaint
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_u, 'role', 'authenticated')::text, true);
  select public.submit_complaint_secure('feedback', 'body-plaintext') into v_cid;
  if v_cid is null then raise exception 'FAIL: submit must return id'; end if;

  -- 2. Verify encrypted at rest
  reset role;
  select body_encrypted into v_enc from public.complaints where id = v_cid;
  if v_enc = convert_to('body-plaintext', 'UTF8') then raise exception 'FAIL: body must be encrypted at rest'; end if;

  -- 3. Scenario A: Submitter user queries v_my_complaints and sees exactly 1 row (own complaint metadata)
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_u, 'role', 'authenticated')::text, true);
  select count(*), max(category), max(status::text) into v_cnt, v_cat, v_stat from public.v_my_complaints where id = v_cid;
  if v_cnt <> 1 then raise exception 'FAIL: submitter must see exactly 1 complaint in v_my_complaints, got %', v_cnt; end if;
  if v_cat <> 'feedback' or v_stat <> 'NEW' then raise exception 'FAIL: metadata mismatch in v_my_complaints'; end if;

  -- 4. Scenario C: Non-admin user queries public.complaints directly and gets 0 rows (table deny policy verified)
  select count(*) into v_cnt from public.complaints where id = v_cid;
  if v_cnt <> 0 then raise exception 'FAIL: non-admin must see 0 rows from public.complaints table directly, got %', v_cnt; end if;

  -- 5. Submitter cannot decrypt complaint (only admin or assigned priest decrypts)
  begin
    v_body := public.decrypt_complaint(v_cid);
    raise exception 'FAIL: submitter parishioner must be FORBIDDEN to decrypt';
  exception when others then
    if sqlerrm not like '%FORBIDDEN%' then raise; end if;
  end;

  -- 6. Scenario B: Different authenticated user queries v_my_complaints and sees 0 rows
  perform set_config('request.jwt.claims', json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
  select count(*) into v_cnt from public.v_my_complaints where id = v_cid;
  if v_cnt <> 0 then raise exception 'FAIL: other user must see 0 rows in v_my_complaints, got %', v_cnt; end if;

  -- Other user direct table read returns 0 rows
  select count(*) into v_cnt from public.complaints where id = v_cid;
  if v_cnt <> 0 then raise exception 'FAIL: other user must see 0 rows from public.complaints table directly'; end if;

  -- Other user cannot decrypt
  begin
    v_body := public.decrypt_complaint(v_cid);
    raise exception 'FAIL: other user must be FORBIDDEN to decrypt';
  exception when others then
    if sqlerrm not like '%FORBIDDEN%' then raise; end if;
  end;

  -- 7. Scenario D: Admin user queries v_complaints and sees submitted complaint metadata
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  select count(*), max(category), max(status::text) into v_cnt, v_cat, v_stat from public.v_complaints where id = v_cid;
  if v_cnt <> 1 then raise exception 'FAIL: admin must see submitted complaint in v_complaints, got %', v_cnt; end if;
  if v_cat <> 'feedback' or v_stat <> 'NEW' then raise exception 'FAIL: metadata mismatch in v_complaints'; end if;

  -- Admin decrypts complaint plaintext
  select public.decrypt_complaint(v_cid) into v_body;
  if v_body <> 'body-plaintext' then raise exception 'FAIL: admin decrypt'; end if;

  -- 8. Missing key raises COMPLAINT_KEY_MISSING / COMPLAINTS_KEY_NOT_SET
  reset role;
  perform set_config('request.jwt.claims', null, true);
  delete from vault.decrypted_secrets where name = 'COMPLAINTS_KEY';
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  begin
    v_body := public.decrypt_complaint(v_cid);
    raise exception 'FAIL: missing key must raise';
  exception when others then
    if sqlerrm not like '%COMPLAINT_KEY_MISSING%' and sqlerrm not like '%COMPLAINTS_KEY_NOT_SET%' then raise; end if;
  end;
  reset role;
  perform set_config('request.jwt.claims', null, true);
  perform vault.create_secret('test-complaints-key', 'COMPLAINTS_KEY');

  reset role;
  raise notice 'OK';
end $$;
