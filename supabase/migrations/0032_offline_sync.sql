-- 0032: Offline-First Sync Schema & RPCs (Docker-Free / Cloud Native)
-- Ensure required extensions are active
create extension if not exists "pgcrypto" with schema extensions;
create extension if not exists "pg_cron" with schema extensions;

-- Table: offline_sync_log (Tracks offline mutation sync attempts and idempotency)
create table if not exists public.offline_sync_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_mutation_id text not null,
  entity_name text not null,
  action text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  status text not null check (status in ('SUCCESS', 'CONFLICT', 'ERROR')),
  payload jsonb not null default '{}'::jsonb,
  error_message text,
  synced_at timestamptz not null default now(),
  constraint uq_offline_user_mutation unique (user_id, client_mutation_id)
);

-- RLS: mandatory 2-step setup
alter table public.offline_sync_log enable row level security;

create policy "Users can view own sync logs"
  on public.offline_sync_log
  for select
  using (auth.uid() = user_id);

-- Index for efficient client sync status queries
create index if not exists idx_offline_sync_log_user_mutation 
  on public.offline_sync_log (user_id, client_mutation_id);

-- RPC: sync_offline_mutations
-- SECURITY DEFINER RPC to safely process offline sync batches transactionally
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

    -- Idempotency check: skip if client_mutation_id already processed for this user
    if exists (
      select 1 from public.offline_sync_log 
      where user_id = v_user_id and client_mutation_id = v_mutation_id
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
          user_id, client_mutation_id, entity_name, action, status, payload
        ) values (
          v_user_id, v_mutation_id, v_entity, v_action, 'SUCCESS', v_payload
        );

        v_processed := v_processed + 1;
        v_results := v_results || jsonb_build_object(
          'client_mutation_id', v_mutation_id,
          'status', 'SUCCESS'
        );
      exception when others then
        v_errors := v_errors + 1;
        insert into public.offline_sync_log (
          user_id, client_mutation_id, entity_name, action, status, payload, error_message
        ) values (
          v_user_id, v_mutation_id, v_entity, v_action, 'ERROR', v_payload, SQLERRM
        );
        v_results := v_results || jsonb_build_object(
          'client_mutation_id', v_mutation_id,
          'status', 'ERROR',
          'error', 'SYNC_FAILED'
        );
      end;
    else
      v_errors := v_errors + 1;
      insert into public.offline_sync_log (
        user_id, client_mutation_id, entity_name, action, status, payload, error_message
      ) values (
        v_user_id, v_mutation_id, v_entity, v_action, 'ERROR', v_payload, 'UNSUPPORTED_MUTATION'
      );
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
