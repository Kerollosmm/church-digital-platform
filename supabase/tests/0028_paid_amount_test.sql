-- 0028: paid_amount price snapshot test
do $$
declare v_user uuid; v_slot bigint; v_book bigint; v_price int; v_paid int;
begin
  insert into public.users (id, phone, name, role, tenant_id)
  values ('00000000-0000-0000-0000-000000000038', '+201033333338', 'p38', 'PARISHIONER', 1);
  insert into public.service_slots (service_id, starts_at, ends_at, capacity, price, status, tenant_id)
  select id, now() + interval '3 days', now() + interval '3 days 1 hour', 5, 75, 'OPEN', 1
  from public.services limit 1
  returning id, price into v_slot, v_price;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000038', 'role', 'authenticated')::text, true);
  select id into v_book from public.book_slot(v_slot, true);

  reset role;
  select paid_amount into v_paid from public.bookings where id = v_book;
  if v_paid <> 75 then raise exception 'FAIL: book_slot must snapshot slot price (expected 75, got %)', v_paid; end if;

  raise notice 'OK';
end $$;
