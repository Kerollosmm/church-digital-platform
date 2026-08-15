-- 0034: admin pins (memorized 2nd factor for admin web login)

create table if not exists public.admin_pins (
  user_id uuid primary key references public.users(id) on delete cascade,
  pin_hash text not null,
  attempts integer not null default 0,
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.admin_pins enable row level security;
-- no RLS policies: SECURITY DEFINER RPCs only (matches event_outbox pattern)

-- 1. set_admin_pin
create or replace function public.set_admin_pin(p_pin text)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_pin is null or p_pin !~ '^[0-9]{4,6}$' then
    raise exception 'INVALID_PIN' using errcode = '22023';
  end if;

  insert into public.admin_pins (user_id, pin_hash, attempts, locked_until, created_at, updated_at)
  values (
    auth.uid(),
    extensions.crypt(p_pin, extensions.gen_salt('bf')),
    0,
    null,
    now(),
    now()
  )
  on conflict (user_id) do update set
    pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf')),
    attempts = 0,
    locked_until = null,
    updated_at = now();
end $$;

-- 2. reset_admin_pin
create or replace function public.reset_admin_pin(p_target uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if not public.is_super_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  delete from public.admin_pins where user_id = p_target;
end $$;

-- 3. admin_pin_status
create or replace function public.admin_pin_status()
returns text
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_rec public.admin_pins;
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select * into v_rec from public.admin_pins where user_id = auth.uid();
  if v_rec is null then
    return 'UNSET';
  end if;

  if v_rec.locked_until is not null and v_rec.locked_until > now() then
    return 'LOCKED';
  end if;

  return 'SET';
end $$;

-- 4. verify_admin_pin
create or replace function public.verify_admin_pin(p_pin text)
returns boolean
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_rec public.admin_pins;
  v_new_attempts integer;
begin
  if not public.is_admin() then
    return false;
  end if;

  select * into v_rec from public.admin_pins where user_id = auth.uid();
  if v_rec is null then
    return false;
  end if;

  -- Lockout check
  if v_rec.locked_until is not null and v_rec.locked_until > now() then
    return false;
  end if;

  -- Lock expired, reset lock state
  if v_rec.locked_until is not null and v_rec.locked_until <= now() then
    v_rec.attempts := 0;
    v_rec.locked_until := null;
  end if;

  -- Verify pin hash
  if v_rec.pin_hash = extensions.crypt(p_pin, v_rec.pin_hash) then
    update public.admin_pins
    set attempts = 0, locked_until = null, updated_at = now()
    where user_id = auth.uid();
    return true;
  else
    v_new_attempts := v_rec.attempts + 1;
    if v_new_attempts >= 5 then
      update public.admin_pins
      set attempts = v_new_attempts, locked_until = now() + interval '15 minutes', updated_at = now()
      where user_id = auth.uid();
    else
      update public.admin_pins
      set attempts = v_new_attempts, updated_at = now()
      where user_id = auth.uid();
    end if;
    return false;
  end if;
end $$;

grant execute on function public.set_admin_pin(text) to authenticated;
grant execute on function public.reset_admin_pin(uuid) to authenticated;
grant execute on function public.admin_pin_status() to authenticated;
grant execute on function public.verify_admin_pin(text) to authenticated;
