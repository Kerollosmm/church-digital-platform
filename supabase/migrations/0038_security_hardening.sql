-- 0038: security hardening & tenant precedence migration for existing deployments
create or replace function public.tenant_id()
returns bigint
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    (select u.tenant_id::text from public.users u where u.id = auth.uid() and u.deleted_at is null),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'tenant_id',
    '1'
  )::bigint
$$;

grant execute on function public.tenant_id() to anon, authenticated, service_role;

-- Offline-sync hardening: allow retry for failed/errored mutations (skip only SUCCESS)
create or replace function public.sync_offline_mutations(
  p_mutations jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid;
  v_item jsonb;
  v_mutation_id text;
  v_entity text;
  v_action text;
  v_payload jsonb;
  v_processed int := 0;
  v_conflicts int := 0;
  v_errors int := 0;
  v_results jsonb := '[]'::jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Authentication required for offline sync';
  end if;

  for v_item in select * from jsonb_array_elements(p_mutations)
  loop
    v_mutation_id := v_item->>'client_mutation_id';
    v_entity := v_item->>'entity_name';
    v_action := v_item->>'action';
    v_payload := coalesce(v_item->'payload', '{}'::jsonb);

    -- Idempotency check: skip only if client_mutation_id already succeeded for this user
    if exists (
      select 1 from public.offline_sync_log 
      where user_id = v_user_id and client_mutation_id = v_mutation_id and status = 'SUCCESS'
    ) then
      v_results := v_results || jsonb_build_object(
        'client_mutation_id', v_mutation_id,
        'status', 'ALREADY_SYNCED'
      );
      continue;
    end if;

    -- Validate and dispatch supported offline mutations
    if v_entity = 'complaints' and v_action = 'INSERT' then
      begin
        perform public.submit_complaint_secure(
          v_payload->>'category',
          v_payload->>'body'
        );

        insert into public.offline_sync_log (
          user_id, client_mutation_id, entity_name, action, status, payload, error_message, synced_at
        ) values (
          v_user_id, v_mutation_id, v_entity, v_action, 'SUCCESS', v_payload, null, now()
        )
        on conflict (user_id, client_mutation_id) do update set
          status = 'SUCCESS',
          payload = excluded.payload,
          error_message = null,
          synced_at = now();

        v_processed := v_processed + 1;
        v_results := v_results || jsonb_build_object(
          'client_mutation_id', v_mutation_id,
          'status', 'SUCCESS'
        );
      exception when others then
        v_errors := v_errors + 1;
        insert into public.offline_sync_log (
          user_id, client_mutation_id, entity_name, action, status, payload, error_message, synced_at
        ) values (
          v_user_id, v_mutation_id, v_entity, v_action, 'ERROR', v_payload, SQLERRM, now()
        )
        on conflict (user_id, client_mutation_id) do update set
          status = 'ERROR',
          payload = excluded.payload,
          error_message = excluded.error_message,
          synced_at = now();

        v_results := v_results || jsonb_build_object(
          'client_mutation_id', v_mutation_id,
          'status', 'ERROR',
          'error', 'SYNC_FAILED'
        );
      end;
    else
      v_errors := v_errors + 1;
      insert into public.offline_sync_log (
        user_id, client_mutation_id, entity_name, action, status, payload, error_message, synced_at
      ) values (
        v_user_id, v_mutation_id, v_entity, v_action, 'ERROR', v_payload, 'UNSUPPORTED_MUTATION', now()
      )
      on conflict (user_id, client_mutation_id) do update set
        status = 'ERROR',
        payload = excluded.payload,
        error_message = excluded.error_message,
        synced_at = now();

      v_results := v_results || jsonb_build_object(
        'client_mutation_id', v_mutation_id,
        'status', 'ERROR',
        'error', 'UNSUPPORTED_MUTATION'
      );
    end if;

  end loop;

  return jsonb_build_object(
    'processed', v_processed,
    'conflicts', v_conflicts,
    'errors', v_errors,
    'details', v_results
  );
end;
$$;

grant execute on function public.sync_offline_mutations(jsonb) to authenticated;
