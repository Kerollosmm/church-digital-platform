# Specification Quality Checklist: Backend Security and Correctness Fixes

**Purpose**: validate specification completeness and quality before implementation  
**Created**: 2026-08-17  
**Reviewed**: 2026-08-17 — all artifacts reconciled against the **live `supabase_db_church` database**,
the working tree, and git history  
**Feature**: [spec.md](../spec.md)

> The first pass of this checklist marked every box `[x]` and declared the spec ready. That verdict was
> not earned: the artifacts it approved contained function signatures, columns, enum labels, and file
> paths that do not exist. This revision records what was actually verified.

## Content Quality

- [x] No implementation details in the spec's user-facing narrative
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders — with the caveat that several requirements now name exact
      catalog objects, because naming them wrongly aborts the migration
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No `[NEEDS CLARIFICATION]` markers remain — the three open design questions were resolved by the
      user: `book_slot` keeps the 2-arg shape plus an idempotency key; the 0051 forward gap is widened
      in 0053; the outbox backlog is backend-only in 007
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic where the requirement permits it
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded — the staff backlog UI and the clean-architecture rework are explicitly
      deferred to feature 008
- [x] Dependencies and assumptions identified, including the two that were previously wrong
      (`dblink` is available but **not installed**; `pg_background` is **unavailable**)

## Schema Verification (added after the first pass proved necessary)

Every item below was checked against the running database, not against the audit prose.

- [x] `apply_payment` signature — it is `(p_payment_id bigint)`. The `(bigint, text, jsonb)` form the
      first draft targeted does not exist, and a `REVOKE` naming it aborts the whole migration
- [x] `service_slots` time columns — `starts_at` / `ends_at`, not `start_time` / `end_time`
- [x] Booking deadline column — `bookings.locked_until`, not `expires_at`
- [x] `booking_status` labels — no `EXPIRED`, no `REFUNDED`; expiry lands on `CANCELLED`
- [x] `event_outbox` columns — exactly `id, tenant_id, handler_type, payload, status, attempts,
      next_attempt_at, created_at`; no `updated_at`, `locked_until`, `retry_count`, or `error_message`.
      The reaper therefore requires new schema
- [x] `event_outbox_attempts_check` bounds attempts to 0–5, so the reaper must branch at the ceiling
      rather than increment unconditionally
- [x] `p0_admin_all` is the **only** policy on `payments`, `audit_log`, `roles_permissions` —
      replacement `SELECT` policies are mandatory, not optional
- [x] `audit_log` and `roles_permissions` have **no `tenant_id` column** — their policies must omit the
      tenant predicate
- [x] `users` has **no `p0_admin_all`** — it uses granular `p0_admin_{read,insert,update,delete}_users`
- [x] `v_available_slots` already derives availability dynamically **and** already carries
      `security_invoker=true` and `WHERE tenant_id = tenant_id()`. Rewriting it would rename two
      columns, drop two more, and remove both the invoker setting and the tenant filter — an RLS/tenant
      bypass plus six broken Dart files. It is explicitly left alone
- [x] Three objects read or write `remaining_capacity`, not one: `fn_restore_slot_capacity_on_cancel`,
      `fn_broadcast_slot_depletion`, `fn_book_slot_atomic`. The `fn_decrement_slot_capacity` named in
      the first draft does not exist
- [x] `fn_broadcast_slot_depletion` emits a `SLOT_EXHAUSTED` realtime signal that must be preserved
- [x] Nine existing test suites reference the dropped column or the view's column names — `0007`,
      `0008`, `0009`, `0010`, `0012`, `0021`, `0035`, `0037`, `0047`
- [x] `rbac_allows(app_role, text, text)` is PUBLIC-executable, unguarded, and has **no caller** in any
      routine or policy — it was absent from the original hardening scope and is now in FR-002
- [x] `active_booking_count` needs **no** change — read-only, and `v_available_slots` depends on it.
      The audit's claim to the contrary is a false positive
- [x] Seven PUBLIC-executable routines already guard internally and are out of scope
- [x] `youtube-expiry` pg_cron job (jobid 4, `0 4 * * *`) is **live** and must be unscheduled
- [x] Video client footprint spans **both** apps. The admin screen
      `apps/admin/lib/features/videos/videos_admin_screen.dart` performs `from('videos').insert(...)`
      and was omitted entirely from the first draft. Mobile paths are `features/video/` (**singular**)
      and `repositories/videos_repository.dart` (**plural**)
- [x] `p_opt_in` is the **WhatsApp opt-in** flag, passed by name from the mobile repository and asserted
      in a test — renaming it breaks the RPC call
- [x] Outbox template allow-list verified; there is **no `payment_receipt`** template and none is added
- [x] `/tests` is **not mounted** inside `supabase_db_church`, so `psql -f /tests/<file>` cannot work;
      suites run over stdin. `run_all.sql` has CRLF endings and unresolvable `\ir` paths over stdin
- [x] `f663168` is an ancestor of `main` and did edit `0043`/`0044` in place, adding 12
      `TO authenticated` clauses that `db push` environments never received. A working-tree diff cannot
      reveal this — the commit had to be inspected directly

## Cross-Artifact Consistency

- [x] Migration numbering is consistent across `plan.md`, `data-model.md`, `tasks.md`, `quickstart.md`,
      and both contracts: `0052_super_admin_role.sql` + `0053_backend_security_and_correctness_fixes.sql`
- [x] Test filenames are consistent: `0053_security_fixes_test.sql`, `0053_concurrency_test.sql`
- [x] The two-migration split is justified by `55P04 unsafe_new_enum_value_usage` in every artifact that
      mentions it, and there is no prior `ALTER TYPE` in the repo to pattern-match against
- [x] Every FR maps to at least one task, including FR-011, which had **zero** tasks in the first draft
- [x] Quickstart commands are bash, matching this session's shell

## Constitution & Invariant Conflicts (recorded, not hidden)

- [x] **`AGENTS.md:33`** — "unauthorized `UPDATE`/`DELETE` must assert 0 rows affected, not exceptions"
      is correct for RLS-level denial but impossible for grant-level denial, which raises
      `42501 insufficient_privilege`. Carve-out carried as task T002, and T002 blocks the US1 tests
- [x] **`AGENTS.md:31`** hardcodes `ADMIN|PRIEST|SUPER_ADMIN`. Purging `PRIEST` requires amending the
      invariant, carried as task T055
- [x] **Test-first exceptions** are declared rather than claimed as PASS: US3 is a deletion whose
      verification is an absence assertion written alongside the drops; US5's role assertions cannot
      parse until `0052` has added the enum label. Both are recorded in `plan.md`'s Constitution Check
- [x] **Quickstart Gate 6 vs. the new fail-fast** — module-scope Paymob validation prevents the function
      from booting when secrets are unset, which would fail the Arabic 401 sweep for the wrong reason.
      Resolved by requiring non-`"0"` placeholders in `supabase/functions/.env`, **not** by weakening
      the check and **not** by adding an error code

## Handoff Decision Coverage

- [x] Decisions 1, 2, 3, 4 (backend only in 007), 10, 12, 13, 14, 15, 23, 24, 25 are all reflected.
      Decisions 12 (delete `specs/005-admin-domain-layer` and `specs/006-mobile-domain-layer`) and 23
      (document the `tenant_id()` fallback) were **missing** from the first draft and are now tasks
      T067 and T066

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets the measurable outcomes in Success Criteria
- [x] Scope boundary with feature 008 is explicit

## Notes

- 8 blockers, 4 high findings, and roughly 10 medium findings from the first draft have been corrected
  across all nine artifacts. The blockers were: the non-existent `apply_payment` signature; the
  `v_available_slots` rewrite; the single-migration enum hazard; the `p0_admin_all` drop without
  replacement policies; the outbox reaper built on five non-existent columns; the non-existent
  `EXPIRED`/`REFUNDED` statuses and `bookings.expires_at`; the omitted admin-app video footprint; and
  FR-011 having no tasks.
- Two open risks are documented rather than resolved: the `ALTER TYPE` path is untested in this repo
  (verify with a clean `db reset` before merge), and the wider in-place migration-edit history on `main`
  is recorded but not remediated, so `supabase db reset` remains the only reliable route to a
  known-good schema.
- Ready for implementation.
