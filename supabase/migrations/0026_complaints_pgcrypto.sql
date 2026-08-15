-- 0026: complaints crypto in-DB (replaces complaints-encrypt/decrypt edge functions)
create or replace function public.submit_complaint_secure(p_category text, p_body text)
returns bigint language plpgsql security definer set search_path = public, extensions as $$
declare
  v_user uuid := auth.uid();
  v_key text;
  v_id bigint;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED' using errcode = '28000'; end if;
  if p_category is null or p_body is null or length(p_body) > 4000
  then raise exception 'BAD_REQUEST'; end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'COMPLAINTS_KEY' limit 1;
  if v_key is null then raise exception 'COMPLAINT_KEY_MISSING: complaints encryption key not provisioned in Vault' using errcode = 'P0002'; end if;
  insert into public.complaints (user_id, category, body_encrypted, tenant_id)
  values (v_user, p_category, pgp_sym_encrypt(p_body, v_key), public.tenant_id())
  returning id into v_id;
  -- audit: complaints trigger (trg_complaints_audit) owns the row; nothing manual (single-writer rule)
  return v_id;
end $$;

create or replace function public.decrypt_complaint(p_complaint_id bigint)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare
  v_role text := public.current_user_role();
  v_row public.complaints;
  v_key text;
begin
  select * into v_row from public.complaints where id = p_complaint_id;
  if v_row is null then raise exception 'COMPLAINT_NOT_FOUND'; end if;
  -- mirror v_complaints (0005): admin/super, or the assigned user (priest only when assigned)
  if v_role not in ('ADMIN','SUPER_ADMIN') and v_row.assigned_to <> auth.uid()
  then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'COMPLAINTS_KEY' limit 1;
  if v_key is null then raise exception 'COMPLAINT_KEY_MISSING: complaints encryption key not provisioned in Vault' using errcode = 'P0002'; end if;
  return pgp_sym_decrypt(v_row.body_encrypted, v_key)::text;
end $$;

grant execute on function public.submit_complaint_secure(text, text) to authenticated;
grant execute on function public.decrypt_complaint(bigint) to authenticated, service_role;
