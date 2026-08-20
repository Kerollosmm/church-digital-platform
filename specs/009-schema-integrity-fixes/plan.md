# Implementation Plan: Schema Integrity Fixes

**Branch**: `009-schema-integrity-fixes` | **Date**: 2026-08-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/009-schema-integrity-fixes/spec.md`

## Summary

A direct review of the running database found three features silently non-functional because `vault.secrets`
is empty, an unintended email registration path, and a set of integrity gaps the schema currently permits.
This plan restores the broken paths first, then closes the integrity gaps, then removes a role abstraction
that never existed, then realigns the constitution with the shipped product.

The technical approach is eight forward-only migrations (`0055`–`0062`), each paired with a registered SQL
test, plus four non-SQL changes: `config.toml`, `supabase/seed.sql`, the ops runbook, and an ADR with a
constitution amendment.

`/speckit-tasks` resolved the one numbering question this plan left open — the `handle_new_user` hardening takes
its own migration (`0056`) rather than folding into `0055`, because it belongs to US2 while the vault work
belongs to US1, and bundling them would make the two P1 stories impossible to ship or revert independently.
That shifts every later migration by one. See `tasks.md` for the final assignment.

Two things shape the sequencing. First, every violating-row count in the live database is zero, so each
constraint can be added and validated in a single step with no data repair. Second, eight live RLS policies
depend on `is_admin_or_priest()`, so that function's removal must recreate the policies before dropping the
function — `CASCADE` would drop the policies and silently remove access control from eight tables.

## Technical Context

**Language/Version**: PostgreSQL 15 (Supabase), Deno/TypeScript for edge functions, Dart/Flutter 3.x for apps

**Primary Dependencies**: Supabase (Postgres, GoTrue, PostgREST, Realtime, Storage), `pg_cron`, `pg_net`,
`supabase_vault`, `pgcrypto`, `btree_gist`

**Storage**: PostgreSQL — 23 tables in `public`, all with RLS enabled, 13 views, migrations applied through `0054`

**Testing**: Transactional SQL tests (`BEGIN ... ROLLBACK`) registered in `supabase/tests/run_all.sql`, executed
through `.agents/skills/backend-smoke-test/scripts/run-gate2-sql.ps1`, which parses TAP output via
`parse-tap.ps1` rather than trusting the `psql` exit code

**Target Platform**: Supabase-hosted Postgres; local stack via Supabase CLI on Docker

**Project Type**: Backend schema and security remediation — no new user-facing surface

**Performance Goals**: No regression. `materialize_analytics` stays a nightly batch; the added constraints are
row-level checks with negligible cost

**Constraints**: Forward-only migrations; no edits to applied migrations; RLS on every table; state transitions
through `SECURITY DEFINER` RPCs; Arabic-first error messages

**Scale/Scope**: Single-church deployment. 8 migrations, 8 new tests, 1 test deleted, 8 policies recreated,
2 views dropped and recreated with their grants restored, 12 constraints added or removed, 2 enums created,
1 enum dropped

## Constitution Check

*GATE: evaluated against `.specify/memory/constitution.md` v1.0.0 (ratified 2026-08-17).*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Test-First (NON-NEGOTIABLE) | PASS | Each migration ships test-first: failing test, verify red, minimal migration, verify green, commit. All tests transactional and registered in `run_all.sql`. TAP output is parsed, never the exit code |
| II. Security by Default | PASS | No new write paths. The eight recreated policies keep identical admin-only semantics. Vault secrets stay in vault — the seed provisions local development values only, and production provisioning is documented, not committed |
| III. Forward-Only Migrations | PASS | Migrations `0055`–`0062`, no in-place edits. Each carries a single concern per the "general hardening gets its own migration and test" rule |
| IV. Arabic-First | N/A | No user-facing strings change. No new error codes; existing `message_ar` catalog untouched |
| V. Deep Modules, Thin Handlers | N/A | No handler or shared-seam changes |
| Product Truth: single church (line 22) | PASS | Tenant fixes harden internal scaffolding only. No isolation test suite, no multi-church UI, no ADR amending line 22 requested |
| Product Truth: video (lines 24-25) | **VIOLATION — being remediated** | Lines 24-25 still present two video types as ratified truth after 007 removed video. Governance requires an owner decision in `docs/adr/` plus a date bump, so this ships as ADR `0002` then the amendment. See Complexity Tracking |
| Governance: one speckit command at a time | NOTED | `.specify/feature.json` was repointed from `specs/007-backend-security-fixes` to this feature. It is a single shared pointer; no other speckit session may run concurrently |

### Gate outcome

Proceed. The single violation is the stale constitution text itself, and remediating it is in scope via the
process Governance prescribes. No principle is being waived.

## Project Structure

### Documentation (this feature)

```text
specs/009-schema-integrity-fixes/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output — verified findings, non-findings, open questions
├── data-model.md        # Phase 1 output — schema deltas
├── quickstart.md         # Phase 1 output — validation guide
├── contracts/
│   └── schema-contracts.md   # Constraint, enum, policy, and RPC contracts
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
supabase/
├── migrations/
│   ├── 0055_vault_preflight.sql              # US1 — surface missing secrets loudly
│   ├── 0056_harden_handle_new_user.sql       # US2 — remove the UUID-as-phone fallback
│   ├── 0057_integrity_constraints.sql        # US3 — CHECKs, drop redundant bookings.status CHECK
│   ├── 0058_status_enums.sql                 # US3 — slot_status, waitlist_status, view drop/recreate/re-grant
│   ├── 0059_tenant_scaffolding.sql           # US4 — keys, defaults, policies, materialize_analytics
│   ├── 0060_remove_priest_abstraction.sql    # US5 — recreate 8 policies, then drop function
│   ├── 0061_user_delete_semantics.sql        # US6 — explicit ON DELETE RESTRICT
│   └── 0062_drop_video_privacy_enum.sql      # US7 — orphan enum
├── tests/
│   ├── 0055_vault_preflight_test.sql
│   ├── 0056_handle_new_user_test.sql
│   ├── 0057_integrity_constraints_test.sql
│   ├── 0058_status_enums_test.sql
│   ├── 0059_tenant_scaffolding_test.sql
│   ├── 0060_priest_abstraction_removal_test.sql
│   ├── 0061_user_delete_semantics_test.sql
│   ├── 0062_video_privacy_removal_test.sql
│   ├── 0005_priest_self_assign_test.sql      # DELETED — tests a role that does not exist
│   └── run_all.sql                           # register new tests, deregister 0005
├── seed.sql                                  # US1 — local vault secrets
└── config.toml                               # US2 — [auth.email] enable_signup = false

docs/
├── adr/
│   └── 0002-video-to-event-booking-pivot.md  # US7 — record the already-made decision
└── ops/
    └── runbook.md                            # US1 — production vault provisioning; US6 — hard delete unsupported

.specify/memory/constitution.md               # US7 — amend lines 24-25, bump version
```

**Structure Decision**: Existing layout, no new directories. Migrations and their tests are numerically
paired, which is the convention through `0054`. `docs/adr/` already holds `0001-v1-domain-model-refinements.md`,
so the pivot ADR is `0002`.

## Build Sequence

Ordered by priority, then by dependency. Each step is test-first per Principle I.

### Step 1 — `0055` vault preflight and provisioning (US1, P1)

The three broken features share one root cause, so this lands first.

- Add a function that reports which of `COMPLAINTS_KEY`, `SUPABASE_URL`, `SERVICE_ROLE_KEY` are absent from
  `vault.decrypted_secrets`, so a missing secret fails loudly instead of degrading to a null URL.
- Provision local values in `supabase/seed.sql`. `SUPABASE_URL` must be `http://kong:8000` — the database
  container's own loopback is not Kong (see `research.md`).
- Document production provisioning in `docs/ops/runbook.md`. Real secrets are never committed.
- Wire the preflight into the smoke-test gate so an unprovisioned environment fails before it is declared healthy.

Verification is end-to-end, not just the function: a complaint must round-trip through
`submit_complaint_secure` / `decrypt_complaint`, and a seeded outbox row must leave `PENDING`.

### Step 2 — `0056` and `config.toml` close email signup (US2, P1)

Set `enable_signup = false` under `[auth.email]`. Separately, change `handle_new_user` so a missing phone
number fails loudly rather than substituting `new.id::text`. The fallback is what makes the open path produce
convincing junk accounts; removing it means the constraint does the work.

The `handle_new_user` change is a trigger-function replacement, so it ships as migration `0056` — not as a
`config.toml`-only change, because the fallback would otherwise remain as a live hazard even with signup closed.

### Step 3 — `0057` integrity constraints (US3, P2)

All counts are zero, so add and validate in one step:

`service_slots` gains `ends_at > starts_at`, `capacity >= 0`, `price >= 0`. `bookings` gains `seat_count >= 1`.
`payments` gains `amount >= 0`. `media_assets` gains `(content_type IS NULL) = (content_id IS NULL)`. The
redundant `bookings.status` CHECK that re-lists the `booking_status` values is dropped, leaving the enum as the
single source of truth.

### Step 4 — `0058` status enums (US3, P2)

Create `slot_status` as `(OPEN, CLOSED)` and `waitlist_status` as `(WAITING, OFFERED)` — exactly the values in
use, none invented. Convert `service_slots.status` and `waiting_list.status`.

`waiting_list` is empty. `service_slots` holds only `OPEN`. The admin app writes `'CLOSED'` as a string through
PostgREST, which casts to the enum, so no client change is needed. Every SQL comparison site
(`0008`, `0015`, `0017`, `0028`, `0048`, `0053`) must be re-checked for resolution after conversion.

Two views block the conversion and must be handled inside this migration. `v_available_slots` and
`v_schedule_today` (`0024_transition_engine.sql:62` and `:78`) both reference `service_slots.status`, and
Postgres refuses a column type change while a view depends on the column. Drop both, convert, recreate — then
restore the `SELECT` grants to `anon, authenticated` that `0050_explicit_read_grants.sql:63-64` established,
because a recreated view loses its grants. Omitting the re-grant silently removes the mobile app's slot listing.

### Step 5 — `0059` tenant scaffolding (US4, P2)

Repoint `payments_monthly` to PK `(tenant_id, month)` and rewrite `materialize_analytics` so both its `DELETE`
and its `INSERT` are tenant-scoped. Add `audit_log.tenant_id bigint NOT NULL DEFAULT tenant_id()` and a tenant
predicate to its policy. Repoint `whatsapp_optins` to PK `(tenant_id, phone)`, add the default, make the column
`NOT NULL`, and add a tenant predicate to its policy.

Both `payments_monthly` and `audit_log` are empty, so these are lossless. Scope is limited to making the
scaffolding self-consistent — no isolation suite, per constitution line 22.

### Step 6 — `0060` remove the priest abstraction (US5, P3)

Order is load-bearing. Recreate all eight policies against `is_admin()` **first**, then
`DROP FUNCTION public.is_admin_or_priest()` without `CASCADE`. The function body is exactly
`select public.is_admin()`, so the substitution preserves behavior.

Delete `supabase/tests/0005_priest_self_assign_test.sql` and deregister it from `run_all.sql`.

The paired test must assert that all eight tables still deny non-admin access *after* the function is gone —
that is the assertion that would catch an accidental `CASCADE`.

### Step 7 — `0061` user delete semantics (US6, P3)

Convert the four `NO ACTION` foreign keys into `users` — `bookings.user_id`, `complaints.user_id`,
`complaints.assigned_to`, `waiting_list.user_id` — to explicit `ON DELETE RESTRICT`, and document hard delete
as unsupported in favor of `users.deleted_at`. No erasure RPC; see `research.md` for why it is deferred rather
than rejected.

### Step 8 — `0062` and constitution realignment (US7, P3)

Drop the orphan `video_privacy` enum. Write `docs/adr/0002-video-to-event-booking-pivot.md` recording the
decision already made on 2026-08-17, then amend constitution lines 24-25 to describe the event booking model
and bump the version to 1.1.0 with a Last Amended date.

This should land before 008 planning begins, since 008 reads the constitution as Product Truth.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| Constitution lines 24-25 contradict the shipped product | 008 planning treats the constitution as Product Truth, so stale video text will misdirect it toward a cancelled feature | Leaving it and relying on AGENTS.md / memory-bank was rejected: those already record the pivot and the contradiction survived anyway. Governance requires an ADR plus a date bump, so the amendment cannot be done informally |
| Eight migrations rather than one | Principle III requires general hardening to get its own migration and test; bundling would make any single failure hard to isolate and impossible to revert independently | One combined migration was rejected because a failure in the policy-recreation step would be entangled with unrelated constraint work, and the drop-ordering risk in step 6 deserves its own reviewable unit |
| Repointing `.specify/feature.json` | It is the single shared speckit pointer and `setup-plan.ps1` reads it, not the git branch | Leaving it on 007 was rejected because the script would have written this plan over 007's completed, committed artifacts |

## Post-Design Constitution Re-Check

*Re-evaluated after Phase 1 produced `data-model.md`, `contracts/schema-contracts.md`, and `quickstart.md`.*

| Principle | Status | What the design added |
|-----------|--------|----------------------|
| I. Test-First (NON-NEGOTIABLE) | PASS | Every contract in `contracts/schema-contracts.md` is stated as an observable assertion, so each test is writable before its migration. The contracts file makes one rule explicit that the plan only implied: a rejection must be asserted as a rejection (`throws_ok`), never as an absence of rows, because the absence form passes vacuously when the insert never ran |
| II. Security by Default | PASS | Design tightened two things. `vault_preflight()` is contracted to return secret *names* only — never a value, in output or in an error. And the eight-policy contract now requires asserting that a non-admin is *denied* after the drop, not merely that eight policies exist: a dropped policy leaves a table open, which is a silent grant rather than a visible error |
| III. Forward-Only Migrations | PASS | `0055`–`0062`, one concern each, no in-place edits. `data-model.md` groups deltas by migration so each stays independently reviewable and revertible |
| IV. Arabic-First | N/A | Unchanged. No user-facing string, error code, or `message_ar` entry is touched |
| V. Deep Modules, Thin Handlers | N/A | Unchanged. No handler or shared seam |
| Product Truth: single church (line 22) | PASS | Held under pressure. `contracts/schema-contracts.md` records the tenant assertions as *shape* assertions only, and states that no test attempts cross-tenant separation. This is the boundary that keeps US4 from drifting into multi-church work |
| Product Truth: video (lines 24-25) | VIOLATION — remediation designed | Unchanged from the initial gate. `quickstart.md` step 10 gives the violation an executable exit condition: no constitution line presents video as current Product Truth, ADR `0002` exists, version is `1.1.0` with a Last Amended date |

### New findings from Phase 1

Three things the design surfaced that the initial gate did not:

1. **`ends_at > starts_at` needs a null-`schedule_range` case of its own.** The contracts file lists it as a
   separate assertion, because that is precisely the case the existing `schedule_range`-only guard misses and is
   the reason the constraint exists. Testing only `ends_at < starts_at` with a populated range would pass
   against the old schema too, and prove nothing.

2. **Acceptance contracts are as load-bearing as rejection contracts.** `capacity = 0`, `price = 0`, and
   `amount = 0` are all legitimate — free and zero-capacity slots are real. A `> 0` constraint written where
   `>= 0` was intended would break them, so the accepted-input table is part of the contract rather than an
   afterthought.

3. **`NO ACTION` to `RESTRICT` is not a behavior change.** The two differ only in deferrability. `0060`'s value
   is entirely in the error message an operator sees, so `data-model.md` states that plainly rather than
   implying a functional fix.

### Re-check outcome

Proceed to `/speckit-tasks`. No principle is waived. The single violation is the stale constitution text, its
remediation is in scope through the route Governance prescribes, and Phase 1 gave it a verifiable exit
condition.
