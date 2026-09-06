# Quickstart: Validating Schema Integrity Fixes

A runnable validation guide. Every step below produces evidence you can read; none of them require trusting a
process exit code.

Constraint definitions live in [`contracts/schema-contracts.md`](./contracts/schema-contracts.md) and schema
deltas in [`data-model.md`](./data-model.md). This file does not repeat them.

## Prerequisites

- Docker running, with the local Supabase stack up
- Supabase CLI on `PATH`
- `psql` reachable — either installed locally, or via `docker exec supabase_db_church psql -U postgres -d postgres`

Local stack ports for this project:

| Service | Port |
|---------|------|
| API (Kong) | 54321 |
| Database | 54323 |
| Studio | 54334 |
| Mailpit | 54335 |

Database URL used throughout:

```text
postgresql://postgres:postgres@127.0.0.1:54323/postgres
```

## The one rule that governs all verification

`psql` exits `0` even when SQL assertions inside the script fail. A green exit code proves the script parsed,
not that it passed.

Never verify with `psql -f ... ; if ($?) { "pass" }`. Always parse the TAP output:

```powershell
.\.agents\skills\backend-smoke-test\scripts\run-gate2-sql.ps1 `
  -DbUrl "postgresql://postgres:postgres@127.0.0.1:54323/postgres"
```

`run-gate2-sql.ps1` captures both stdout and stderr, pipes them to `parse-tap.ps1`, and returns a verdict
derived from the TAP lines. That verdict is the evidence. This is spec.md's SC-008 and it applies to every step
in this guide.

## Step 0 — Reset and apply

```powershell
supabase db reset
```

This replays every migration from `0001` through `0062` and runs `supabase/seed.sql`, which is where the local
vault secrets are provisioned.

Expected: the reset completes and reports the migration list including `0055` through `0062`.

## Step 1 — Vault preflight (US1)

Confirm the three secrets exist and the preflight agrees.

```powershell
psql "postgresql://postgres:postgres@127.0.0.1:54323/postgres" -c "select name from vault.decrypted_secrets order by name;"
psql "postgresql://postgres:postgres@127.0.0.1:54323/postgres" -c "select * from public.vault_preflight();"
```

Expected: the first query lists `COMPLAINTS_KEY`, `SERVICE_ROLE_KEY`, `SUPABASE_URL`. The second returns
**zero rows**.

Then confirm it fails loudly. Inside a transaction that you roll back:

```sql
begin;
  delete from vault.secrets where name = 'COMPLAINTS_KEY';
  select * from public.vault_preflight();
rollback;
```

Expected: exactly one row, `COMPLAINTS_KEY`. No secret value appears in the output.

`SUPABASE_URL` must be `http://kong:8000`. A loopback address resolves to the database container itself, not to
Kong, so `127.0.0.1` there produces a silent dispatch failure rather than an error.

## Step 2 — Complaints round-trip (SC-001)

This is the end-to-end proof that US1 actually restored the feature. A schema assertion cannot prove it.

Submit a complaint through the RPC, then decrypt it as an admin, and compare the plaintext.

Expected: the stored body is ciphertext, `decrypt_complaint` returns the original text, and no
`COMPLAINT_KEY_MISSING` is raised anywhere in the path.

## Step 3 — Outbox leaves PENDING (SC-002)

Seed an `event_outbox` row, then let the dispatcher run — it fires on a one-minute `pg_cron` schedule.

```sql
select status, attempts, last_error from public.event_outbox order by created_at desc limit 5;
```

Expected: within two dispatcher cycles the seeded row's status is no longer `PENDING`.

A row still `PENDING` with `attempts = 0` and a null `last_error` means the dispatch is still no-oping — the URL
is null and `net.http_post` silently did nothing. Re-check `SUPABASE_URL` before looking anywhere else.

## Step 4 — Email signup is closed (SC-004)

Confirm the config:

```powershell
Select-String -Path supabase\config.toml -Pattern 'enable_signup' -Context 2,0
```

Expected: `enable_signup = false` under `[auth.email]`.

Then attempt an email signup against the local API and confirm rejection. Mailpit at
`http://127.0.0.1:54335` should receive no confirmation mail.

Separately confirm the trigger no longer hides the consequence:

```sql
select count(*) from public.users where phone ~* '^[0-9a-f]{8}-[0-9a-f]{4}-';
```

Expected: `0`. A non-zero count means a UUID is sitting in a phone column — either the fallback is still present
or a pre-existing junk account needs cleanup.

## Step 5 — Constraints reject invalid data (SC-005)

Run the suite through the gate script, not by hand:

```powershell
.\.agents\skills\backend-smoke-test\scripts\run-gate2-sql.ps1 `
  -DbUrl "postgresql://postgres:postgres@127.0.0.1:54323/postgres"
```

Expected: verdict `PASS`, zero TAP failures.

The suite covers every rejection and acceptance row in `contracts/schema-contracts.md`. Each rejection is
asserted as a rejection — a test that inserts an invalid row and then asserts the table is empty would pass even
if the insert had never been attempted, so no test in this feature is written that way.

Spot-check the enums directly:

```sql
select enum_range(null::slot_status), enum_range(null::waitlist_status);
select to_regtype('video_privacy') is null as video_privacy_gone;
```

Expected: `{OPEN,CLOSED}`, `{WAITING,OFFERED}`, and `t`.

## Step 6 — Admin slot closing still works (contract regression)

The enum conversion touches the one column the admin app writes directly. Confirm the write path survived:

```powershell
psql "postgresql://postgres:postgres@127.0.0.1:54323/postgres" -c "update public.service_slots set status = 'CLOSED' where id = (select id from public.service_slots limit 1) returning id, status;"
```

Expected: the update succeeds and returns `CLOSED`. PostgREST sends the same string literal, so this proves the
admin app's path.

Then confirm the two views the enum conversion had to drop came back with their grants:

```sql
select has_table_privilege('anon', 'public.v_available_slots', 'SELECT')      as anon_slots,
       has_table_privilege('authenticated', 'public.v_available_slots', 'SELECT') as auth_slots,
       has_table_privilege('anon', 'public.v_schedule_today', 'SELECT')       as anon_today,
       has_table_privilege('authenticated', 'public.v_schedule_today', 'SELECT')  as auth_today;
```

Expected: `t` for all four. A `f` here produces no SQL error — the views work fine for the service role — it
just empties the mobile app's slot listing.

## Step 7 — Analytics idempotency (SC-007)

```sql
select public.materialize_analytics();
create temp table snap as select * from public.payments_monthly;
select public.materialize_analytics();
select count(*) from (
  (select * from snap except select * from public.payments_monthly)
  union all
  (select * from public.payments_monthly except select * from snap)
) d;
```

Expected: `0`. Also confirm no rollup row has a null `tenant_id`.

## Step 8 — Eight policies survived the function drop (SC-006)

This is the step that would catch an accidental `CASCADE`.

```sql
select tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
  and policyname in ('announcements admin write','faq admin write','priests admin write',
                     'service_slots admin write','services admin write','p_analytics_read_admin')
order by tablename, policyname;

select to_regprocedure('public.is_admin_or_priest()') is null as function_gone;

select count(*) from pg_policies where schemaname = 'public' and qual like '%is_admin_or_priest%';
```

Expected: **eight** policy rows, `function_gone = t`, and `0` policies still referencing the old function.

Eight rows alone is not sufficient. The suite must also assert that a non-admin session is denied on each of the
eight tables, because a dropped policy leaves a table open rather than closed — the absence of a policy is not a
visible error, it is a silent grant.

## Step 9 — User delete is explicitly restricted (SC-009)

```sql
begin;
  delete from public.users where id = (select user_id from public.bookings limit 1);
rollback;
```

Expected: an error naming the `bookings_user_id_fkey` restriction. Confirm the delete action is recorded as
`RESTRICT`, reading from `pg_constraint` rather than from the Studio export, which omits `ON DELETE` clauses
entirely:

```sql
select conname, confdeltype
from pg_constraint
where conname in ('bookings_user_id_fkey','complaints_user_id_fkey',
                  'complaints_assigned_to_fkey','waiting_list_user_id_fkey');
```

Expected: `confdeltype = 'r'` for all four.

## Step 10 — Constitution realignment (SC-010)

```powershell
Select-String -Path .specify\memory\constitution.md -Pattern 'video' -CaseSensitive:$false
Test-Path docs\adr\0002-video-to-event-booking-pivot.md
```

Expected: no line presents video as current Product Truth, the ADR exists, and the constitution version is
`1.1.0` with a Last Amended date.

## Before applying to production

The zero-violating-row counts that let every constraint be added in a single step were measured against the
**local** database. Re-measure them against production before applying `0057`, `0059`, or `0061` there:

```sql
select
  (select count(*) from service_slots where ends_at <= starts_at) as slots_bad_order,
  (select count(*) from service_slots where capacity < 0)         as slots_neg_cap,
  (select count(*) from service_slots where price < 0)            as slots_neg_price,
  (select count(*) from bookings where seat_count < 1)            as seat_lt1,
  (select count(*) from payments where amount < 0)                as pay_neg,
  (select count(*) from media_assets
     where (content_type is null) <> (content_id is null))        as media_half,
  (select count(*) from whatsapp_optins where tenant_id is null)  as wa_null_tenant,
  (select count(*) from audit_log)                                as audit_rows,
  (select count(*) from payments_monthly)                         as pm_rows;
```

Every column must read `0`. A non-zero value means that migration needs a data repair step that this plan does
not include.

Production vault provisioning is documented in `docs/ops/runbook.md`. Real secret values are never committed to
this repository — `supabase/seed.sql` carries local development values only.
