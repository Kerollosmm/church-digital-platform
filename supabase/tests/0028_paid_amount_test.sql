BEGIN;

-- 0028: paid_amount price snapshot test
do $$
declare v_user uuid; v_slot bigint; v_book bigint; v_price int; v_paid int;
begin
  insert into auth.users (id, instance_id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000038', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p38@test.local', '+201033333338', '{}', '{}', now(), now())
  on conflict (id) do nothing;
  update public.users set role = 'USER', tenant_id = 1, deleted_at = null where id = '00000000-0000-0000-0000-000000000038';
  delete from public.bookings where user_id = '00000000-0000-0000-0000-000000000038';
  insert into public.service_slots (service_id, starts_at, ends_at, capacity, price, status, tenant_id)
  select id, now() + interval '3 days', now() + interval '3 days 1 hour', 5, 75, 'OPEN', 1
  from public.services limit 1
  returning id, price into v_slot, v_price;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000038', 'role', 'authenticated')::text, true);
  select id into v_book from public.book_slot(p_slot_id => v_slot, p_opt_in => true);

  reset role;
  select paid_amount into v_paid from public.bookings where id = v_book;
  if v_paid <> 75 then raise exception 'FAIL: book_slot must snapshot slot price (expected 75, got %)', v_paid; end if;

  raise notice 'OK';
end $$;

ROLLBACK;
