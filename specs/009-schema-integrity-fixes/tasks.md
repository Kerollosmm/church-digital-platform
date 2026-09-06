---

description: "Task list for 009-schema-integrity-fixes"
---

# Tasks: Schema Integrity Fixes

**Input**: Design documents from `/specs/009-schema-integrity-fixes/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/schema-contracts.md`, `quickstart.md`

**Tests**: REQUIRED, not optional. Constitution Principle I is NON-NEGOTIABLE and spec FR-022 requires every
migration to be paired with a test registered in `run_all.sql`. Every story below is written test-first:
write the test, verify it fails, write the minimal migration, verify it passes.

**Organization**: Tasks are grouped by user story so each can be implemented, tested, and shipped independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US7)
- Exact file paths are included in every task

## Path Conventions

- Migrations: `supabase/migrations/`
- Tests: `supabase/tests/`, registered in `supabase/tests/run_all.sql`
- Docs: `docs/`
- Gate script: `.agents/skills/backend-smoke-test/scripts/`

## Migration numbering

`plan.md` deferred one decision to this phase: whether the `handle_new_user` hardening folds into `0055` or
takes its own number. It takes its own number. It belongs to US2 while the vault work belongs to US1, and
bundling them would make the two P1 stories impossible to ship or revert independently.

Final assignment — eight migrations, `0055` through `0062`:

| Migration | Story | Concern |
|-----------|-------|---------|
| `0055_vault_preflight.sql` | US1 | Surface missing vault secrets loudly |
| `0056_harden_handle_new_user.sql` | US2 | Remove the UUID-as-phone fallback |
| `0057_integrity_constraints.sql` | US3 | Six CHECKs added, one redundant CHECK dropped |
| `0058_status_enums.sql` | US3 | `slot_status`, `waitlist_status`, view drop/recreate/re-grant |
| `0059_tenant_scaffolding.sql` | US4 | Keys, defaults, policies, `materialize_analytics` |
| `0060_remove_priest_abstraction.sql` | US5 | Recreate 8 policies, then drop the function |
| `0061_user_delete_semantics.sql` | US6 | Explicit `ON DELETE RESTRICT` |
| `0062_drop_video_privacy_enum.sql` | US7 | Orphan enum |

## Two hazards found while planning these tasks

Both were discovered by reading source, not by reasoning from the schema, and both are silent failures.

**Hazard A — the enum conversion is blocked by two views, and recreating them drops their grants.**
`v_available_slots` and `v_schedule_today` (both defined at `supabase/migrations/0024_transition_engine.sql:62`
and `:78`) reference `service_slots.status`. Postgres refuses `ALTER COLUMN ... TYPE` while a view depends on
the column, so `0058` must drop both views, convert, then recreate them. Recreating a view drops its grants,
and `supabase/migrations/0050_explicit_read_grants.sql:63-64` grants `SELECT` on both to `anon, authenticated`.
Omitting the re-grant silently removes the mobile app's slot listing. T031 asserts the grants.

**Hazard B — a test that emits no TAP output is invisible to the gate.**
`parse-tap.ps1` counts `ok N` / `not ok N` lines. The `DO $$ ... RAISE EXCEPTION 'FAIL: ...' $$` style used by
`0019` and `0045` emits none, so such a test contributes zero positive evidence that it ran. It still fails
loudly when it raises, but a test that silently no-ops looks identical to one that never existed. Every new
test in this feature uses pgTAP (`ok`, `throws_ok`, `is`) so each assertion emits a countable line.

---

## Phase 1: Setup

**Purpose**: Bring the environment up and capture the evidence baseline everything else is measured against.

- [x] T001 Start the local stack with `supabase start` and confirm API 54321, DB 54323, Studio 54334, Mailpit 54335 are reachable
- [x] T002 [P] Confirm the applied migration head is `0054` by listing `supabase/migrations/` and querying `supabase_migrations.schema_migrations`
- [x] T003 Run `.agents/skills/backend-smoke-test/scripts/run-gate2-sql.ps1 -DbUrl "postgresql://postgres:postgres@127.0.0.1:54323/postgres"` and record the baseline verdict and `OkCount`/`TotalTests` in the PR description

---

## Phase 2: Foundational (Blocking Prerequisites)

**⚠️ CRITICAL**: No story work begins until both tasks pass.

- [x] T004 Verify `pgtap` is installable (`CREATE EXTENSION IF NOT EXISTS pgtap;`) and adopt the TAP-emitting test skeleton for all eight new files: `\set ON_ERROR_STOP on`, `CREATE EXTENSION IF NOT EXISTS pgtap;`, `BEGIN;`, `SELECT no_plan();`, assertions, `SELECT * FROM finish();`, `ROLLBACK;` — matching `supabase/tests/0053_security_fixes_test.sql`, not the DO-block style
- [x] T005 Re-measure the nine violating-row counts from `specs/009-schema-integrity-fixes/quickstart.md` ("Before applying to production") against the target database; every column must read `0` before any constraint migration is written

**Checkpoint**: Environment green, baseline recorded, zero violating rows confirmed. Stories may begin.

---

## Phase 3: User Story 1 - Restore the three dead features (Priority: P1) 🎯 MVP

**Goal**: `vault.secrets` is provisioned, a missing secret fails loudly, and complaints, dispatch, and
reconciliation work again.

**Independent Test**: A complaint round-trips through `submit_complaint_secure` / `decrypt_complaint`, and a
seeded outbox row leaves `PENDING`.

### Tests for User Story 1

- [x] T006 [P] [US1] Write `supabase/tests/0055_vault_preflight_test.sql` asserting the three contracts in `contracts/schema-contracts.md` § `public.vault_preflight()`: zero rows when all secrets present; exactly the removed name when one is deleted inside the transaction; and that no result value matches any `vault.decrypted_secrets.decrypted_secret`
- [x] T007 [US1] Run the gate script and confirm `0055_vault_preflight_test.sql` FAILS because `vault_preflight()` does not exist

### Implementation for User Story 1

- [x] T008 [US1] Create `supabase/migrations/0055_vault_preflight.sql` defining `public.vault_preflight() returns setof text` as `stable security definer set search_path to ''`, returning the name of each of `COMPLAINTS_KEY`, `SUPABASE_URL`, `SERVICE_ROLE_KEY` absent from `vault.decrypted_secrets`; grant execute to `service_role` only, never to `authenticated`
- [x] T009 [US1] Provision the three secrets for local development in `supabase/seed.sql` using `vault.create_secret`, with `SUPABASE_URL` set to `http://kong:8000` — a loopback address resolves to the database container itself, not to Kong (see `research.md`)
- [x] T010 [US1] Register `\ir 0055_vault_preflight_test.sql` in `supabase/tests/run_all.sql` after the `0054` entry
- [x] T011 [US1] Run `supabase db reset`, then the gate script; confirm the test now passes and the suite verdict is PASS
- [x] T012 [US1] Add a production vault provisioning section to `docs/ops/runbook.md` covering all three secrets, stating that real values are never committed and that `supabase/seed.sql` holds local development values only
- [x] T013 [US1] Wire `select * from public.vault_preflight();` into `.agents/skills/backend-smoke-test/scripts/run-gate2-sql.ps1` so an unprovisioned environment fails before the suite is declared healthy; the check must fail the gate when any row is returned
- [x] T014 [US1] Verify SC-001 end to end: submit a complaint through `submit_complaint_secure`, confirm the stored body is ciphertext, decrypt it through `decrypt_complaint`, and confirm the plaintext matches and no `COMPLAINT_KEY_MISSING` was raised
- [x] T015 [US1] Verify SC-002 end to end: seed an `event_outbox` row and confirm it leaves `PENDING` within two dispatcher cycles; a row still `PENDING` with `attempts = 0` and a null `last_error` means the URL is still null

**Checkpoint**: Complaints, notification dispatch, and payment reconciliation are functional. This is the MVP.

---

## Phase 4: User Story 2 - Close the email registration path (Priority: P1)

**Goal**: Phone OTP is the only way an account can exist, and a missing phone fails instead of becoming a UUID.

**Independent Test**: An email signup is rejected, and no `public.users.phone` value parses as a UUID.

### Tests for User Story 2

- [x] T016 [P] [US2] Write `supabase/tests/0056_handle_new_user_test.sql` asserting: an `auth.users` insert with a phone produces a matching `public.users` row; an insert with a null or empty phone raises via `throws_ok` and leaves `public.users` unchanged; and `select count(*) from public.users where phone ~* '^[0-9a-f]{8}-[0-9a-f]{4}-'` is `0`
- [x] T017 [US2] Run the gate script and confirm the test FAILS — today the no-phone insert silently succeeds with `new.id::text`

### Implementation for User Story 2

- [x] T018 [US2] Create `supabase/migrations/0056_harden_handle_new_user.sql` replacing `public.handle_new_user()` so the `coalesce(nullif(new.phone, ''), new.id::text)` fallback raises instead of substituting; keep `security definer`, `set search_path to ''`, fully qualified writes, and `on conflict (id) do nothing`
- [x] T019 [US2] Set `enable_signup = false` under `[auth.email]` in `supabase/config.toml` (currently `true` at line 221)
- [x] T020 [US2] Register `\ir 0056_handle_new_user_test.sql` in `supabase/tests/run_all.sql`, then run `supabase db reset` and the gate script; confirm PASS
- [x] T021 [US2] Confirm `supabase/seed.sql` still applies cleanly — all four seeded `auth.users` rows carry a phone (`supabase/seed.sql:4-19`), so the hardened trigger must not break the reset
- [x] T022 [US2] Verify SC-004 manually: attempt an email signup against `http://127.0.0.1:54321`, confirm rejection, and confirm Mailpit at `http://127.0.0.1:54335` received no confirmation mail

**Checkpoint**: Both P1 stories complete. The two active incidents are closed.

---

## Phase 5: User Story 3 - Make the database reject impossible data (Priority: P2)

**Goal**: Six CHECK constraints added, one redundant CHECK dropped, two free-text status columns converted to
enums — with the admin write path and the two dependent views intact.

**Independent Test**: Every rejection row in `contracts/schema-contracts.md` is rejected, every acceptance row
is accepted.

### Tests for User Story 3

- [x] T023 [P] [US3] Write `supabase/tests/0057_integrity_constraints_test.sql` covering every constraint row in `contracts/schema-contracts.md` § Rejection contracts using `throws_ok` — never by asserting an absence of rows, which passes vacuously when the insert never ran — including the `ends_at < starts_at` case with `schedule_range` null, which is the specific gap the old range-only guard missed
- [x] T024 [US3] Extend `0057_integrity_constraints_test.sql` with the acceptance contracts: `capacity = 0`, `price = 0`, `amount = 0`, `seat_count = 1`, both-null and both-set `media_assets`, and every value of `booking_status` after the redundant CHECK is dropped
- [x] T025 [US3] Run the gate script and confirm `0057_integrity_constraints_test.sql` FAILS on every rejection assertion

### Implementation for User Story 3 — constraints

- [x] T026 [US3] Create `supabase/migrations/0057_integrity_constraints.sql` adding the six constraints named in `data-model.md` § `0057`: `service_slots_time_order_chk` (strict `>`, not `>=`), `service_slots_capacity_nonneg_chk`, `service_slots_price_nonneg_chk`, `bookings_seat_count_min_chk`, `payments_amount_nonneg_chk`, `media_assets_polymorphic_chk`
- [x] T027 [US3] In the same migration, drop the redundant `bookings.status` CHECK that re-lists the six `booking_status` values, leaving the enum as the single source of truth
- [x] T028 [US3] Register `\ir 0057_integrity_constraints_test.sql` in `supabase/tests/run_all.sql`, reset, run the gate script, confirm PASS

### Tests for User Story 3 — enums

- [x] T029 [P] [US3] Write `supabase/tests/0058_status_enums_test.sql` asserting `enum_range(null::slot_status) = '{OPEN,CLOSED}'`, `enum_range(null::waitlist_status) = '{WAITING,OFFERED}'`, `throws_ok` on `service_slots.status = 'PENDING'` and `waiting_list.status = 'EXPIRED'`, and acceptance of `'CLOSED'` and `'OFFERED'` sent as strings
- [x] T030 [US3] Run the gate script and confirm `0058_status_enums_test.sql` FAILS because neither enum type exists

### Implementation for User Story 3 — enums

- [x] T031 [US3] Create `supabase/migrations/0058_status_enums.sql` creating `slot_status` as `(OPEN, CLOSED)` and `waitlist_status` as `(WAITING, OFFERED)` — exactly the values in use, none invented; the waiting-list lifecycle gap stays an open question in `research.md` rather than being guessed at
- [x] T032 [US3] In the same migration, drop `public.v_available_slots` and `public.v_schedule_today` before altering `service_slots.status`, since Postgres refuses a column type change while a view depends on the column (Hazard A)
- [x] T033 [US3] Convert `service_slots.status` to `slot_status` and `waiting_list.status` to `waitlist_status`, preserving each column's existing default
- [x] T034 [US3] Recreate both views verbatim from `supabase/migrations/0024_transition_engine.sql:62-88`, keeping `security_invoker = true`
- [x] T035 [US3] Re-grant `SELECT ON public.v_schedule_today` and `SELECT ON public.v_available_slots` to `anon, authenticated`, restoring what `supabase/migrations/0050_explicit_read_grants.sql:63-64` established — a recreated view loses its grants, and omitting this silently removes the mobile app's slot listing (Hazard A)
- [x] T036 [US3] Add grant assertions to `supabase/tests/0058_status_enums_test.sql`: `has_table_privilege('anon', 'public.v_available_slots', 'SELECT')` and the same for `authenticated` and `v_schedule_today`
- [x] T037 [US3] Register `\ir 0058_status_enums_test.sql` in `supabase/tests/run_all.sql`, reset, run the gate script, confirm PASS
- [x] T038 [US3] Verify every comparison site still resolves by exercising the RPCs that contain them rather than by reading the files — the sites are in migrations `0008`, `0015`, `0017`, `0028`, `0048`, `0053`
- [x] T039 [US3] Verify the admin write path survives: `update public.service_slots set status = 'CLOSED'` returns `CLOSED`, matching what `apps/admin/lib/features/slots/slots_admin_screen.dart:37` sends through PostgREST

**Checkpoint**: The database now rejects impossible rows, and both dependent views still serve `anon`.

---

## Phase 6: User Story 4 - Make the tenant scaffolding internally correct (Priority: P2)

**Goal**: The three deviating tables match the pattern every other table follows.

**Independent Test**: Each table's key and default match the pattern; `materialize_analytics` is idempotent.

**Scope boundary**: Constitution line 22 ratifies single-church deployment. These are *shape* assertions only.
No test attempts to prove cross-tenant separation, and no ADR amending line 22 is requested.

### Tests for User Story 4

- [x] T040 [P] [US4] Write `supabase/tests/0059_tenant_scaffolding_test.sql` asserting: `payments_monthly` primary key is `(tenant_id, month)`; `whatsapp_optins` primary key is `(tenant_id, phone)`; `audit_log.tenant_id` and `whatsapp_optins.tenant_id` are both `NOT NULL` with default `tenant_id()`; inserting into either without naming `tenant_id` yields `tenant_id()`; and both policies' `qual` text references `tenant_id`
- [x] T041 [US4] Add the idempotency assertion to the same file: run `materialize_analytics()` twice and assert the full contents of `payments_monthly` compare equal, plus `count(*) filter (where tenant_id is null) = 0`
- [x] T042 [US4] Run the gate script and confirm `0059_tenant_scaffolding_test.sql` FAILS

### Implementation for User Story 4

- [x] T043 [US4] Create `supabase/migrations/0059_tenant_scaffolding.sql` repointing `payments_monthly` to primary key `(tenant_id, month)` — the table is empty and fully rebuilt by `materialize_analytics`, so this is lossless
- [x] T044 [US4] In the same migration, rewrite `public.materialize_analytics()` so both its `DELETE FROM public.payments_monthly` and its `INSERT` are scoped by `tenant_id`
- [x] T045 [US4] In the same migration, add `audit_log.tenant_id bigint NOT NULL DEFAULT tenant_id()` and add a tenant predicate to its policy, which is currently a bare `USING is_admin()`
- [x] T046 [US4] In the same migration, repoint `whatsapp_optins` to primary key `(tenant_id, phone)`, add `DEFAULT tenant_id()`, make the column `NOT NULL`, and add a tenant predicate to its policy — re-confirm `wa_null_tenant = 0` first, since unlike the other two tables this one may hold rows
- [x] T047 [US4] Register `\ir 0059_tenant_scaffolding_test.sql` in `supabase/tests/run_all.sql`, reset, run the gate script, confirm PASS

**Checkpoint**: The scaffolding no longer contradicts itself, and no reviewer needs to re-investigate it.

---

## Phase 7: User Story 5 - Remove the priest abstraction (Priority: P3)

**Goal**: `is_admin_or_priest()` is gone and all eight policies still deny non-admin access.

**Independent Test**: Eight policies present, function absent, non-admin denied on all eight tables.

> **Ordering is load-bearing.** Recreate all eight policies against `is_admin()` **first**, then
> `DROP FUNCTION public.is_admin_or_priest()` **without** `CASCADE`. `CASCADE` would drop the eight policies
> themselves, removing access control from eight tables while the migration reported success. A dropped policy
> is a silent grant, not a visible error.

### Tests for User Story 5

- [x] T048 [P] [US5] Write `supabase/tests/0060_priest_abstraction_removal_test.sql` asserting `to_regprocedure('public.is_admin_or_priest()') is null`, that exactly the eight policies listed in `contracts/schema-contracts.md` § Policy contracts are present in `pg_policies`, and that `count(*) from pg_policies where qual like '%is_admin_or_priest%'` is `0`
- [x] T049 [US5] Add the assertion that actually matters to the same file: for each of the eight tables, a non-admin session is denied — asserted *after* the function is gone. Policy existence alone does not prove access is controlled
- [x] T050 [US5] Run the gate script and confirm `0060_priest_abstraction_removal_test.sql` FAILS because the function still exists

### Implementation for User Story 5

- [x] T051 [US5] Create `supabase/migrations/0060_remove_priest_abstraction.sql` recreating all eight policies against `is_admin()`: `announcements admin write`, `faq admin write`, `priests admin write`, `service_slots admin write`, `services admin write` (each `ALL`), and `p_analytics_read_admin` on `bookings_monthly`, `payments_monthly`, `slot_utilization_monthly` (each `SELECT`)
- [x] T052 [US5] In the same migration, after the eight policies are recreated, `DROP FUNCTION public.is_admin_or_priest()` with no `CASCADE`; the body is exactly `select public.is_admin()`, so the substitution is behavior-preserving
- [x] T053 [US5] Delete `supabase/tests/0005_priest_self_assign_test.sql`, which tests a role that does not exist
- [x] T054 [US5] Deregister `\ir 0005_priest_self_assign_test.sql` from `supabase/tests/run_all.sql:8` and register `\ir 0060_priest_abstraction_removal_test.sql`
- [x] T055 [US5] Reset, run the gate script, confirm PASS and that the total assertion count dropped only by what `0005` contributed

**Checkpoint**: The dead abstraction is gone with access control provably intact.

---

## Phase 8: User Story 6 - Make user deletion semantics explicit (Priority: P3)

**Goal**: Hard delete fails with a named constraint instead of a confusing mid-cascade abort.

**Independent Test**: Deleting a user who has a booking is rejected with a named constraint.

### Tests for User Story 6

- [x] T056 [P] [US6] Write `supabase/tests/0061_user_delete_semantics_test.sql` asserting `pg_constraint.confdeltype = 'r'` for `bookings_user_id_fkey`, `complaints_user_id_fkey`, `complaints_assigned_to_fkey`, and `waiting_list_user_id_fkey`; that deleting a `public.users` row with a booking raises; and that deleting the corresponding `auth.users` row also raises, since the cascade hits the same restriction
- [x] T057 [US6] Run the gate script and confirm the constraint-type assertions FAIL — all four are currently `NO ACTION` (`confdeltype = 'a'`)

### Implementation for User Story 6

- [x] T058 [US6] Create `supabase/migrations/0061_user_delete_semantics.sql` dropping and re-adding the four foreign keys with explicit `ON DELETE RESTRICT`; `NO ACTION` and `RESTRICT` differ only in deferrability, so the value here is entirely in the error an operator sees
- [x] T059 [US6] Register `\ir 0061_user_delete_semantics_test.sql` in `supabase/tests/run_all.sql`, reset, run the gate script, confirm PASS
- [x] T060 [US6] Document in `docs/ops/runbook.md` that hard user deletion is unsupported and `users.deleted_at` is the supported path; note that an anonymizing erasure RPC is deferred, not rejected, since Egypt's PDPL (Law 151/2018) grants erasure rights

**Checkpoint**: The latent delete trap is now a clear, named error.

---

## Phase 9: User Story 7 - Realign the constitution with the shipped product (Priority: P3)

**Goal**: The orphan enum is gone and no constitution line presents video as current Product Truth.

**Independent Test**: `to_regtype('video_privacy') is null`, ADR `0002` exists, constitution version is `1.1.0`.

**Why this should land before 008 planning**: 008 reads the constitution as Product Truth, so stale video text
will actively misdirect it toward a cancelled feature.

### Tests for User Story 7

- [x] T061 [P] [US7] Write `supabase/tests/0062_video_privacy_removal_test.sql` asserting `to_regtype('video_privacy') is null`; keep it separate from `supabase/tests/0019_videos_test.sql`, which already asserts the table and RPC removal and stays as is
- [x] T062 [US7] Run the gate script and confirm the test FAILS because the enum still exists

### Implementation for User Story 7

- [x] T063 [US7] Create `supabase/migrations/0062_drop_video_privacy_enum.sql` dropping the `video_privacy` type; no table, view, function, or column references it, so no `CASCADE` is needed and none should be used
- [x] T064 [US7] Register `\ir 0062_video_privacy_removal_test.sql` in `supabase/tests/run_all.sql`, reset, run the gate script, confirm PASS
- [x] T065 [US7] Write `docs/adr/0002-video-to-event-booking-pivot.md` recording the decision already made on 2026-08-17, following the format of `docs/adr/0001-v1-domain-model-refinements.md`
- [x] T066 [US7] Amend `.specify/memory/constitution.md` lines 24-25 to describe the event booking model instead of two video types, bump the version to `1.1.0`, and add a Last Amended date — the ADR must exist first, since Governance requires an owner decision before an amendment

**Checkpoint**: All seven stories complete. 008 planning can now read the constitution safely.

---

## Phase 10: Polish & Cross-Cutting Concerns

- [x] T067 Run the full suite through `.agents/skills/backend-smoke-test/scripts/run-gate2-sql.ps1` and confirm verdict PASS with zero `not ok` lines, zero `ERROR:` lines, and a `TotalTests` count higher than the T003 baseline (SC-008)
- [x] T068 Walk `specs/009-schema-integrity-fixes/quickstart.md` steps 0-10 end to end on a fresh `supabase db reset` and confirm every expected result
- [x] T069 [P] Update `memory-bank/activeContext.md` with the 009 outcome, the eight migrations, and the two hazards recorded above
- [x] T070 [P] Confirm `docs/ops/runbook.md` covers both additions — vault provisioning (T012) and unsupported hard delete (T060) — as one coherent section rather than two disconnected notes
- [x] T071 Re-measure the nine violating-row counts against production and record them in the PR before `0057`, `0059`, or `0061` are applied there; a non-zero count means that migration needs a data repair step this plan does not include

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all stories
- **US1 (Phase 3)**: Depends on Foundational. No dependency on any other story
- **US2 (Phase 4)**: Depends on Foundational. Independent of US1
- **US3 (Phase 5)**: Depends on Foundational. `0058` depends on `0057` only by migration order, not by content
- **US4 (Phase 6)**: Depends on Foundational. Independent
- **US5 (Phase 7)**: Depends on Foundational. Touches `payments_monthly`'s policy, which US4 also touches — see below
- **US6 (Phase 8)**: Depends on Foundational. Independent
- **US7 (Phase 9)**: Depends on Foundational. T066 depends on T065
- **Polish (Phase 10)**: Depends on all stories

### The one real cross-story dependency

US4 (`0059`) and US5 (`0060`) both touch `payments_monthly`. US4 changes its primary key; US5 recreates its
`p_analytics_read_admin` policy. Migration order resolves this — `0059` runs before `0060` — but if the two are
developed in parallel, US5 must recreate the policy against whatever US4 left, not against what it read at the
start. Sequential development in numeric order avoids the question entirely.

### Within each story

- The test is written and verified RED before the migration exists. This is Principle I and it is not optional
- Migration before registration in `run_all.sql`
- Registration before the green run
- Story complete and green before moving to the next priority

### Parallel Opportunities

- T002 runs alongside T001
- Every test-authoring task marked [P] — T006, T016, T023, T029, T040, T048, T056, T061 — is a different file
  with no dependency on another incomplete task, so all eight can be written up front
- T069 and T070 are different files and run together
- With more than one person: US1 and US2 are both P1, fully independent, and can ship in either order

---

## Parallel Example: writing all eight test files first

```bash
Task: "Write supabase/tests/0055_vault_preflight_test.sql"
Task: "Write supabase/tests/0056_handle_new_user_test.sql"
Task: "Write supabase/tests/0057_integrity_constraints_test.sql"
Task: "Write supabase/tests/0058_status_enums_test.sql"
Task: "Write supabase/tests/0059_tenant_scaffolding_test.sql"
Task: "Write supabase/tests/0060_priest_abstraction_removal_test.sql"
Task: "Write supabase/tests/0061_user_delete_semantics_test.sql"
Task: "Write supabase/tests/0062_video_privacy_removal_test.sql"
```

Writing them together is efficient, but each must still be verified RED against the unmigrated schema before
its migration is written. A test that was never seen failing proves nothing.

---

## Implementation Strategy

### MVP first (US1 only)

1. Phase 1: Setup
2. Phase 2: Foundational
3. Phase 3: US1
4. **STOP and VALIDATE**: complaint round-trips, outbox leaves `PENDING`
5. This alone restores three non-functional features, including the refund path. It is worth shipping on its own

### Incremental delivery

1. Setup + Foundational → baseline recorded
2. US1 → the three dead features work → ship
3. US2 → the open registration path is closed → ship
4. US3 → the database rejects impossible rows → ship
5. US4 → the scaffolding stops contradicting itself → ship
6. US5, US6, US7 → clarity and governance → ship

Each story leaves the suite green, so any prefix of this sequence is a valid stopping point.

### Suggested ordering rationale

US1 and US2 are both P1, but US1 goes first because its failures affect money — the refund path runs through
the outbox that is currently frozen. US7 should land before 008 planning begins regardless of its P3 priority,
since 008 reads the constitution as Product Truth.

---

## Notes

- Every rejection is asserted as a rejection (`throws_ok`), never as an absence of rows. The absence form
  passes vacuously when the insert never ran, which is the failure mode this suite exists to catch
- The `psql` exit code is never the verdict. It returns `0` even when assertions fail. Only the parsed TAP
  output from `parse-tap.ps1` counts as evidence
- Never edit an applied migration in place (Constitution III). Every correction is a new numbered migration
- Real secret values are never committed. `supabase/seed.sql` carries local development values only
- Read delete semantics from `pg_constraint`, never from the Studio visualizer export, which omits every
  `ON DELETE` clause
- Commit after each task or logical group; stop at any checkpoint to validate a story independently
