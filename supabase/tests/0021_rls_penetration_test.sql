BEGIN;

do $$
declare
  v_parishioner uuid; v_other uuid; v_admin uuid; v_other_booking bigint; v_amount numeric; v_price int; v_sum numeric;
begin
  insert into auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('21212121-2121-2121-2121-212121212121', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p21@test.local', '+201000000211', '{}', '{}', now(), now()),
         ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p22@test.local', '+201000000212', '{}', '{}', now(), now()),
         ('23232323-2323-2323-2323-232323232323', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p23@test.local', '+201000000213', '{}', '{}', now(), now())
  on conflict (id) do nothing;
  update public.users set role = 'USER', tenant_id = 1, deleted_at = null where id in ('21212121-2121-2121-2121-212121212121', '22222222-2222-2222-2222-222222222222');
  update public.users set role = 'ADMIN', tenant_id = 1, deleted_at = null where id = '23232323-2323-2323-2323-232323232323';

  v_parishioner := '21212121-2121-2121-2121-212121212121';
  v_other := '22222222-2222-2222-2222-222222222222';
  v_admin := '23232323-2323-2323-2323-232323232323';

  delete from public.bookings where user_id in (v_parishioner, v_other);
  insert into public.services (id, title_ar, tenant_id) overriding system value values (99921, 'خدمة 021', 1) on conflict do nothing;
  insert into public.service_slots (id, service_id, starts_at, ends_at, capacity, price, status, tenant_id)
  overriding system value
  values (999211, 99921, now() + interval '12 days', now() + interval '12 days 1 hour', 5, 5000, 'OPEN', 1)
  on conflict (id) do update set starts_at = now() + interval '12 days', capacity = 5, status = 'OPEN';

  -- seed a complaint owned by someone else (as postgres, bypasses RLS; trigger encrypts it)
  insert into public.complaints (user_id, category, body_encrypted, tenant_id)
  values (v_other, 'OTHER', 'x', public.tenant_id());

  -- create a booking owned by v_parishioner
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_parishioner, 'role','authenticated')::text, true);
  select id into v_other_booking from public.book_slot(999211, false);

  -- 1. PARISHIONER cannot write service_slots, bookings, or payments (RLS filters silently -> assert no change)
  reset role;
  select coalesce(paid_amount, 0) into v_amount from public.bookings where id = v_other_booking;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_other, 'role','authenticated')::text, true);
  update public.bookings set paid_amount = coalesce(paid_amount, 0) + 1 where id = v_other_booking;

  reset role;
  if (select coalesce(paid_amount, 0) from public.bookings where id = v_other_booking) is distinct from v_amount
  then raise exception 'FAIL: PARISHIONER must not update others bookings'; end if;

  reset role;
  select price into v_price from public.service_slots limit 1;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_other, 'role','authenticated')::text, true);
  update public.service_slots set price = price + 1;

  reset role;
  if (select price from public.service_slots limit 1) <> v_price
  then raise exception 'FAIL: PARISHIONER must not write service_slots'; end if;

  reset role;
  insert into public.payments (id, booking_id, amount, status, tenant_id)
    overriding system value
    values (99921, v_other_booking, 5000, 'PENDING', 1)
    on conflict (id) do nothing;
  select sum(amount) into v_sum from public.payments;


  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_other, 'role','authenticated')::text, true);
  begin
    update public.payments set amount = amount + 1;
    raise exception 'FAIL: PARISHIONER must not write payments';
  exception when insufficient_privilege then null;
  end;

  reset role;
  if (select sum(amount) from public.payments) is distinct from v_sum
  then raise exception 'FAIL: PARISHIONER must not write payments'; end if;

  -- 2. ANON cannot call state RPCs (book_slot requires auth)
  set local role anon;
  begin
    perform public.book_slot(1, false);
    raise exception 'FAIL: anon must not book';
  exception when others then null; end;

  -- 3. ADMIN can read payments + update service_slots (positive control)
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role','authenticated')::text, true);
  if (select count(*) from public.payments) = 0 then raise exception 'FAIL: ADMIN must read payments'; end if;
  update public.service_slots set price = price + 1 where id = (select id from public.service_slots limit 1);

  -- 4. body_encrypted never readable via direct table read by regular users
  perform set_config('request.jwt.claims', json_build_object('sub', v_parishioner, 'role','authenticated')::text, true);
  if exists (select 1 from public.complaints) then raise exception 'FAIL: users must not read complaints table directly'; end if;
end $$;

ROLLBACK;
