-- 0056_harden_handle_new_user.sql
-- Harden auth user trigger to require a non-empty phone and eliminate UUID fallback

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text;
begin
  v_phone := nullif(trim(new.phone), '');
  if v_phone is null then
    raise exception 'PHONE_REQUIRED: user must have a valid phone number';
  end if;

  insert into public.users (id, phone, name, tenant_id)
  values (new.id, v_phone, coalesce(new.raw_user_meta_data ->> 'name', ''), 1)
  on conflict (id) do nothing;
  
  return new;
end;
$$;
