BEGIN;

do $$
declare v_slot bigint; v_user uuid; v_price int;
begin
  select id into v_user from public.users where role='USER' order by id limit 1;
  select id into v_slot from public.service_slots limit 1;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role','authenticated')::text, true);
  -- RLS silently filters: a blocked UPDATE affects 0 rows (no exception)
  select price into v_price from public.service_slots where id = v_slot;
  update public.service_slots set price = price + 1 where id = v_slot;
  if (select price from public.service_slots where id = v_slot) <> v_price
  then raise exception 'FAIL: PARISHIONER must not write service_slots'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', (select id from public.users where role='ADMIN' limit 1), 'role','authenticated')::text, true);
  update public.service_slots set price = price + 1 where id = v_slot;
end $$;

ROLLBACK;
