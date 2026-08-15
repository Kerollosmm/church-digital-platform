-- 0026: complaints pgp round-trip + access rules
do $$
declare v_u uuid; v_a uuid; v_cid bigint; v_body text; v_enc bytea; v_role text;
begin
  insert into public.users (id, phone, name, role, tenant_id) values
    ('00000000-0000-0000-0000-000000000021', '+201022222221', 'c', 'PARISHIONER', 1),
    ('00000000-0000-0000-0000-000000000022', '+201022222222', 'c2', 'PARISHIONER', 1),
    ('00000000-0000-0000-0000-000000000023', '+201022222223', 'a', 'ADMIN', 1);

  -- vault key (test-scoped; dev key ships in seed — see Step 2)
  insert into vault.secrets (name, secret) values ('COMPLAINTS_KEY', 'test-complaints-key')
  on conflict (name) do update set secret = excluded.secret;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000021', 'role', 'authenticated')::text, true);
  select public.submit_complaint_secure('feedback', 'body-plaintext') into v_cid;
  if v_cid is null then raise exception 'FAIL: submit must return id'; end if;

  reset role;
  select body_encrypted into v_enc from public.complaints where id = v_cid;
  if v_enc = convert_to('body-plaintext', 'UTF8') then raise exception 'FAIL: body must be encrypted at rest'; end if;

  -- parishioner submitter: FORBIDDEN to decrypt (only admin or assigned priest decrypts)
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000021', 'role', 'authenticated')::text, true);
  begin
    v_body := public.decrypt_complaint(v_cid);
    raise exception 'FAIL: submitter parishioner must be FORBIDDEN to decrypt';
  exception when others then
    if sqlerrm not like '%FORBIDDEN%' then raise; end if;
  end;

  -- other parishioner: FORBIDDEN
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000022', 'role', 'authenticated')::text, true);
  begin
    v_body := public.decrypt_complaint(v_cid);
    raise exception 'FAIL: other user must be FORBIDDEN';
  exception when others then
    if sqlerrm not like '%FORBIDDEN%' then raise; end if;
  end;

  -- admin decrypts any
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000023', 'role', 'authenticated')::text, true);
  select public.decrypt_complaint(v_cid) into v_body;
  if v_body <> 'body-plaintext' then raise exception 'FAIL: admin decrypt'; end if;

  -- missing key -> COMPLAINTS_KEY_NOT_SET
  delete from vault.secrets where name = 'COMPLAINTS_KEY';
  begin
    v_body := public.decrypt_complaint(v_cid);
    raise exception 'FAIL: missing key must raise';
  exception when others then
    if sqlerrm not like '%COMPLAINTS_KEY_NOT_SET%' then raise; end if;
  end;
  insert into vault.secrets (name, secret) values ('COMPLAINTS_KEY', 'test-complaints-key')
  on conflict (name) do update set secret = excluded.secret;

  raise notice 'OK';
end $$;
