-- 0002: helpers + RLS baseline + audit + auto-provisioning. Phase 0 owns 0001-0003.

create or replace function public.tenant_id()
returns bigint
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'tenant_id',
    (select u.tenant_id::text from public.users u where u.id = auth.uid() and u.deleted_at is null),
    '1'
  )::bigint
$$;


create or replace function public.current_user_role()
returns text
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    (select u.role::text from public.users u
     where u.id = auth.uid() and u.deleted_at is null),
    'anon'
  )
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.current_user_role() = 'ADMIN'
$$;

create or replace function public.is_admin_or_priest()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_admin()
$$;

create or replace function public.is_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_admin()
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'users','roles_permissions','priests','services','service_slots','bookings','payments',
    'waiting_list','videos','video_purchases','complaints','announcements','audit_log',
    'whatsapp_outbox','whatsapp_optins']
  loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'users','priests','services','service_slots','bookings','payments','waiting_list',
    'videos','video_purchases','complaints','announcements']
  loop
    execute format('alter table public.%I alter column tenant_id set default public.tenant_id()', t);
  end loop;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'roles_permissions','priests','services','service_slots','bookings','payments',
    'waiting_list','videos','video_purchases','complaints','announcements','audit_log',
    'whatsapp_outbox','whatsapp_optins']
  loop
    execute format($f$
      create policy p0_admin_all on public.%I
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin())
    $f$, t);
  end loop;
end $$;

create policy p0_users_read_own on public.users
  for select to authenticated
  using (id = auth.uid());

-- Admin can read all users
create policy p0_admin_read_users on public.users
  for select to authenticated
  using (public.is_admin());

-- Admin can insert users
create policy p0_admin_insert_users on public.users
  for insert to authenticated
  with check (public.is_admin());

-- Admin can update users but NOT change the role column (use SECURITY DEFINER RPC)
create policy p0_admin_update_users on public.users
  for update to authenticated
  using (public.is_admin())
  with check (
    public.is_admin()
    and role = (select u.role from public.users u where u.id = users.id)
  );

-- Admin can delete users
create policy p0_admin_delete_users on public.users
  for delete to authenticated
  using (public.is_admin());

create policy p0_bookings_read_own on public.bookings
  for select to authenticated
  using (user_id = auth.uid());

create or replace function public.audit_trigger()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.audit_log (user_id, action, entity_type, entity_id, meta)
  values (
    auth.uid(),
    tg_op,
    tg_table_name,
    case when tg_op = 'DELETE' then old.id else new.id end,
    jsonb_build_object(
      'old', case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
      'new', case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end
    )
  );
  return case when tg_op = 'DELETE' then old else new end;
end $$;

create trigger trg_bookings_audit after insert or update or delete on public.bookings
  for each row execute function public.audit_trigger();
create trigger trg_payments_audit after insert or update or delete on public.payments
  for each row execute function public.audit_trigger();
create trigger trg_complaints_audit after insert or update or delete on public.complaints
  for each row execute function public.audit_trigger();

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.users (id, phone, name, tenant_id)
  values (new.id, coalesce(nullif(new.phone, ''), new.id::text), coalesce(new.raw_user_meta_data ->> 'name', ''), 1)
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
