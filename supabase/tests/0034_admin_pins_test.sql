BEGIN;

-- 0034: admin pins test
do $$
declare
  v_status text;
  v_ok boolean;
  v_err text;
begin
  -- Fixtures
  insert into auth.users (id, phone, email) values
    ('00000000-0000-0000-0000-000000000034', '+201000000034', 'admin34@test.com'),
    ('00000000-0000-0000-0000-000000000035', '+201000000035', 'user35@test.com')
  on conflict (id) do nothing;

  insert into public.users (id, phone, name, role, tenant_id) values
    ('00000000-0000-0000-0000-000000000034', '+201000000034', 'admin_test', 'ADMIN', 1),
    ('00000000-0000-0000-0000-000000000035', '+201000000035', 'user_test', 'USER', 1)
  on conflict (id) do update set role = EXCLUDED.role;

  -- 1. Day-1 UNSET status for admin
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000034', 'role', 'authenticated')::text, false);

  v_status := public.admin_pin_status();
  if v_status <> 'UNSET' then
    raise exception 'FAIL: initial admin_pin_status should be UNSET, got %', v_status;
  end if;

  -- 2. USER role forbidden from admin_pin_status and set_admin_pin
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000035', 'role', 'authenticated')::text, false);

  begin
    perform public.admin_pin_status();
    raise exception 'FAIL: user must not call admin_pin_status';
  exception when others then
    if sqlerrm not like '%FORBIDDEN%' then raise; end if;
  end;

  begin
    perform public.set_admin_pin('1234');
    raise exception 'FAIL: user must not call set_admin_pin';
  exception when others then
    if sqlerrm not like '%FORBIDDEN%' then raise; end if;
  end;

  -- Switch back to ADMIN
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000034', 'role', 'authenticated')::text, false);

  -- 3. Invalid PIN format rejected
  begin
    perform public.set_admin_pin('123'); -- too short
    raise exception 'FAIL: 3-digit pin must be rejected';
  exception when others then
    if sqlerrm not like '%INVALID_PIN%' then raise; end if;
  end;

  begin
    perform public.set_admin_pin('1234567'); -- too long
    raise exception 'FAIL: 7-digit pin must be rejected';
  exception when others then
    if sqlerrm not like '%INVALID_PIN%' then raise; end if;
  end;

  begin
    perform public.set_admin_pin('abcd'); -- non-digits
    raise exception 'FAIL: non-digit pin must be rejected';
  exception when others then
    if sqlerrm not like '%INVALID_PIN%' then raise; end if;
  end;

  -- 4. Valid PIN setup & status SET
  perform public.set_admin_pin('123456');

  v_status := public.admin_pin_status();
  if v_status <> 'SET' then
    raise exception 'FAIL: admin_pin_status after set should be SET, got %', v_status;
  end if;

  -- 5. Verify PIN (success & fail)
  v_ok := public.verify_admin_pin('123456');
  if not v_ok then
    raise exception 'FAIL: verify_admin_pin correct pin returned false';
  end if;

  v_ok := public.verify_admin_pin('999999');
  if v_ok then
    raise exception 'FAIL: verify_admin_pin wrong pin returned true';
  end if;

  -- 6. Lockout test (4 more wrong attempts = 5 total fails)
  perform public.verify_admin_pin('999991');
  perform public.verify_admin_pin('999992');
  perform public.verify_admin_pin('999993');
  perform public.verify_admin_pin('999994');

  v_status := public.admin_pin_status();
  if v_status <> 'LOCKED' then
    raise exception 'FAIL: admin_pin_status after 5 fails should be LOCKED, got %', v_status;
  end if;

  -- Correct PIN while locked should return false
  v_ok := public.verify_admin_pin('123456');
  if v_ok then
    raise exception 'FAIL: verify_admin_pin while locked should return false';
  end if;

  -- 7. Reset PIN (by admin/super admin)
  perform public.reset_admin_pin('00000000-0000-0000-0000-000000000034');

  v_status := public.admin_pin_status();
  if v_status <> 'UNSET' then
    raise exception 'FAIL: admin_pin_status after reset should be UNSET, got %', v_status;
  end if;

  raise notice 'OK: 0034 admin pins test passed';
end $$;

ROLLBACK;
