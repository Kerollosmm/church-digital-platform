\set ON_ERROR_STOP on
create schema if not exists tests;
create or replace function tests.expect(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if not p_cond then raise exception 'FAIL: %', p_msg; end if;
end $$;

do $$
declare t text; a text; r record;
begin
  foreach t in array array['users','services','service_slots','bookings','payments','videos',
                           'video_purchases','complaints','announcements'] loop
    foreach a in array array['READ','CREATE','UPDATE','DELETE'] loop
      perform tests.expect(
        exists (select 1 from public.roles_permissions
                where role = 'ADMIN' and resource = t and action = a),
        'ADMIN missing ' || a || ' on ' || t);
    end loop;
  end loop;

  perform tests.expect(
    (select count(*) from public.roles_permissions where role = 'ADMIN') = 36,
    'ADMIN must have exactly 36 rows');
  perform tests.expect(
    (select count(*) from public.roles_permissions where role = 'USER') = 10,
    'USER must have exactly 10 rows');
  perform tests.expect(
    (select count(*) from public.roles_permissions
     where role = 'USER' and action = 'DELETE') = 0,
    'USER must never DELETE');
  perform tests.expect(
    not exists (select 1 from public.roles_permissions where role::text = 'SERVANT'),
    'SERVANT role must not exist in matrix');

  perform tests.expect(
    public.rbac_allows('USER', 'services', 'READ') and
    public.rbac_allows('USER', 'bookings', 'CREATE') and
    public.rbac_allows('USER', 'complaints', 'CREATE'),
    'USER key grants missing');
  perform tests.expect(
    public.rbac_allows('ADMIN', 'complaints', 'DELETE') and
    public.rbac_allows('ADMIN', 'payments', 'DELETE'),
    'ADMIN delete grants missing');
end $$;
