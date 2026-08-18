# Research: 007-backend-security-fixes

**Date**: 2026-08-17 (revised after live-database verification)  
**Status**: Completed  
**Sources**: 2026-08-17 backend audit, **direct inspection of the running `supabase_db_church`
database**, `AGENTS.md`, `.specify/memory/constitution.md`, migrations 0001–0051, and the app trees.

> The first draft of this document repeated several claims from the audit prose that turned out to be
> wrong when checked against the live schema. Corrections are called out inline as **[CORRECTED]** so
> the mistakes are not reintroduced.

---

## R1: RPC-only write boundary on sensitive tables

- **Decision**: `REVOKE INSERT, UPDATE, DELETE` from `anon` and `authenticated` on `payments`,
  `complaints`, `users`, `audit_log`, `roles_permissions`; drop `p0_admin_all`
  (`FOR ALL TO authenticated USING (is_admin())`) from the four tables that carry it; route all
  mutations through `SECURITY DEFINER` RPCs.
- **Rationale**: verified live — `authenticated` holds `INSERT, UPDATE, DELETE, SELECT` on all five
  tables. Any ADMIN can therefore set `payments.status = 'PAID'` straight from the admin app, read
  `complaints.body_encrypted` raw instead of through the Vault-audited `decrypt_complaint`, and edit
  or delete `audit_log` rows. `p0_admin_all` is permissive, so it ORs with the restrictive
  `complaints deny table access` policy and neutralises it.
- **[CORRECTED] Dropping the policy is not sufficient on its own.** `p0_admin_all` is the *only*
  policy on `payments`, `audit_log`, and `roles_permissions`. Dropping it removes admin `SELECT` as
  well, which silently breaks `apps/admin/lib/features/payments/payments_admin_screen.dart:15`. The
  same migration must create explicit admin `SELECT` policies. Note that `audit_log` and
  `roles_permissions` have **no `tenant_id` column**, so their policies must not carry a tenant
  predicate.
- **[CORRECTED] `users` has no `p0_admin_all`.** It uses granular
  `p0_admin_{read,insert,update,delete}_users` policies plus `p0_users_read_own`. Only the grants
  change there.
- **No replacement mutation RPCs are needed for the current apps.** A sweep of `apps/admin/lib` and
  `apps/mobile/lib` found no `insert`/`update`/`delete` against any of the five tables — only reads
  (`payments.select`, `users.select('role')`, `v_complaints`) and the already-guarded
  `decrypt_complaint` RPC. The admin complaints screen reads `assigned_to` but never writes it, so
  `complaints_admin_assign` becomes a dead `UPDATE` policy and is dropped for clarity.
- **Alternatives considered**: RLS `WITH CHECK` only (rejected — permissive policies OR together, which
  is exactly how this hole opened); trigger-based DML blocking (rejected — grant revocation is the
  standard, cheaper primitive).

---

## R2: Privilege hardening for unprotected SECURITY DEFINER functions

- **Decision**: `REVOKE ALL ... FROM PUBLIC, anon, authenticated` and grant narrowly.
- **[CORRECTED] `apply_payment` takes one argument**: `apply_payment(p_payment_id bigint)`. The
  three-argument `(bigint, text, jsonb)` form asserted in the first draft does not exist, and a
  `REVOKE` naming it would abort the migration. Gateway metadata lands in `payments.gateway_ref`,
  `merchant_order_id`, and `raw_webhook` — there are no `gateway_order_id` or `raw_payload` columns.
- **Verified list of SECURITY DEFINER functions left at PostgreSQL's default `EXECUTE TO PUBLIC` with
  no internal caller guard**: `apply_payment(bigint)`, `apply_video_payment(bigint)`,
  `expire_stale_bookings()`, `promote_waiting_list(bigint)`, `materialize_analytics()`,
  `rbac_allows(app_role, text, text)`, plus three trigger functions
  (`handle_new_user`, `enqueue_fcm_booking_status_push`, `fn_broadcast_slot_depletion`) which
  PostgREST cannot invoke because they return `trigger`.
  - `apply_video_payment` is dropped with the video pivot.
  - `rbac_allows` was **not** in the original scope. It has **no caller anywhere** — no function body
    and no policy references it — yet it lets anon enumerate the RBAC matrix. Revoke from
    `PUBLIC, anon`.
- **[CORRECTED] `active_booking_count` needs no change.** The audit listed it among the unguarded
  anon-callable functions. It is read-only, `v_available_slots` depends on it, and hardening it would
  break the view. Left alone deliberately.
- **[CORRECTED] Seven PUBLIC-executable functions are already safe** because they guard internally via
  `current_user_role()`, `is_admin()`, or `auth.uid()`: `decrypt_complaint`, `emergency_override`,
  `cancel_booking`, `confirm_booking`, `complete_booking`, `join_waiting_list`, `manual_book`. Out of
  scope.
- **Alternatives considered**: adding an `is_admin()` check inside `apply_payment` (rejected — the
  Paymob webhook runs as `service_role` with no admin JWT, so grant narrowing matches the real
  operational model).

---

## R3: Total removal of video machinery (product pivot)

- **Decision**: drop tables `videos`, `video_purchases`; drop `payments.video_id`; drop
  `purchase_video(bigint, uuid)`, `apply_video_payment(bigint)`,
  `deliver_personal_video(text, text, text, bigint)`; delete the `youtube-expiry` and
  `deliver-personal-video` edge functions; remove `video_ready` from
  `event_outbox_whatsapp_template_check`; strip the client code.
- **[CORRECTED] The live `youtube-expiry` pg_cron job must be unscheduled.** jobid 4 (`0 4 * * *`)
  POSTs to `/functions/v1/youtube-expiry` and will keep firing at a dead endpoint. The first draft
  referenced a non-existent migration named `0020_youtube_cron` and never scheduled the unschedule.
- **[CORRECTED] The client footprint is wider than the mobile purchase screen.** Verified paths:
  - mobile: `lib/features/video/video_purchase_screen.dart` (directory is `video`, **singular**),
    `lib/repositories/videos_repository.dart` (**plural** filename, not `video_repository.dart`),
    plus references in `app_router.dart`, `home_hub_screen.dart`, `bottom_nav_scaffold.dart`,
    `services/app_strings.dart`, `services/error_mapper.dart`, and six test files.
  - **admin**: `lib/features/videos/videos_admin_screen.dart` — which performs
    `from('videos').insert(...)` — plus `test/features/videos/videos_admin_screen_test.dart` and the
    admin router. The first draft omitted the admin app entirely.
- **Rationale**: both tables verified empty (0 rows), so no data migration. Removing the feature
  eliminates the YouTube token-refresh maintenance and the associated attack surface.
- **Alternatives considered**: soft-deprecate behind an `is_active` flag (rejected — the product
  decision is outright cancellation).

---

## R4: Slot capacity — the drift is in the counter, not the view

- **[CORRECTED] `v_available_slots` already derives availability dynamically** via
  `active_booking_count(s.id)`, and already carries `security_invoker=true` and
  `WHERE s.tenant_id = tenant_id()`. FR-005's dynamic-derivation requirement is satisfied by the
  existing view. The first draft proposed replacing it, which would have been a triple regression:
  renaming `available_seats` → `remaining_capacity` and `slot_status` → `status` (breaking
  `available_slot.dart` and five widget tests), dropping `title_ar`/`location` (breaking the slot grid
  and admin manual-booking screen), and recreating without `security_invoker` or the tenant filter
  (turning the view into an RLS/tenant bypass). It also used `start_time`/`end_time`, which do not
  exist — the columns are `starts_at`/`ends_at`.
- **Decision**: leave the view untouched, pin its column contract with a regression test, and delete
  the redundant counter and its writers.
- **[CORRECTED] Three functions read or write `remaining_capacity`**, not one:
  `fn_restore_slot_capacity_on_cancel` (trigger `tr_restore_slot_capacity` on `bookings`),
  `fn_broadcast_slot_depletion` (trigger `tr_on_slot_depletion` on `service_slots`), and
  `fn_book_slot_atomic` (called by `book_slot`). The `fn_decrement_slot_capacity` named in the first
  draft does not exist. Dropping the column without handling all three leaves broken trigger
  functions.
  - `fn_broadcast_slot_depletion` emits a `SLOT_EXHAUSTED` realtime notification on the
    `remaining_capacity` 1→0 edge. That signal is preserved by emitting the identical `pg_notify`
    payload from the canonical `book_slot` when the post-insert active count reaches `capacity`.
- **[CORRECTED] Nine existing test suites reference `remaining_capacity`, `available_seats`, or
  `slot_status`**: `0007`, `0008`, `0009`, `0010`, `0012`, `0021`, `0035`, `0037`, `0047`. They must be
  audited and updated when the column is dropped. Handoff decision 13 keeps them in their existing
  plain-assert style — it does not exempt them from compiling.
- **Alternatives considered**: repairing every counter trigger (rejected — distributed counters are
  the bug class, not the symptom).

---

## R5: Resilient payment reconciliation

- **Decision**: in `reconcile-payments`, treat non-2xx and timeouts as transient — log with the
  payment id and status, then `continue`. Only call `mark_payment_failed` on an explicit terminal
  Paymob verdict. In `paymob-checkout`, validate the four Paymob secrets at module scope and throw if
  any is absent, empty, or `"0"`.
- **Rationale**: `reconcile-payments/index.ts:48-57` currently fails a payment on any non-2xx, and the
  sweep only re-selects `status = 'CREATED'`, so a real payer is stranded as `FAILED` with no booking.
- **Interaction to respect**: module-scope secret validation prevents the function from booting when
  the variables are unset, which would break the Arabic-error HTTP gate for the wrong reason.
  Quickstart requires non-`"0"` placeholders in `supabase/functions/.env` rather than weakening the
  check or adding a new error code (the error-code contract is frozen).
- **Alternatives considered**: in-request retry (rejected — risks the edge execution timeout;
  deferring to the next sweep is standard for reconciliation).

---

## R6: Outbox recovery and the staff backlog

- **[CORRECTED] The current `event_outbox` cannot support a reaper.** Verified columns are exactly
  `id, tenant_id, handler_type, payload, status, attempts, next_attempt_at, created_at`. There is no
  `updated_at`, no `locked_until`, no `retry_count`, and no `error_message` — every column the first
  draft's reaper and backlog view depended on. 007 must therefore **add schema**:
  `claimed_at timestamptz` (written by `claim_event_outbox_batch` on claim) and `last_error text`
  (written by `event-dispatcher` on failure).
- **[CORRECTED] The reaper cannot blindly increment attempts.**
  `event_outbox_attempts_check` enforces `attempts >= 0 AND attempts <= 5`, so an unconditional
  `attempts + 1` aborts the reaper on a row already at 5. At the ceiling the row is parked as
  `FAILED` with an explanatory `last_error` instead.
- **Decision**: `reap_stuck_outbox_events(p_timeout interval DEFAULT interval '5 minutes')` selecting
  `status = 'PROCESSING' AND claimed_at < now() - p_timeout` with `FOR UPDATE SKIP LOCKED`; pg_cron
  every 5 minutes; `v_failed_outbox_events` plus `admin_resend_outbox_event(bigint)` guarded by
  `is_admin()`.
- **Scope note**: the Flutter staff backlog screen from handoff decision 4 is deferred to feature 008
  with the clean-architecture rework. 007 delivers the view and the RPC only.
- **Alternatives considered**: worker heartbeats (rejected — over-engineered for a Postgres outbox at
  this scale).

---

## R7: Role architecture (`SUPER_ADMIN`, purge `PRIEST`)

- **[CORRECTED] The enum change needs its own migration.** `ALTER TYPE ... ADD VALUE` may run inside a
  transaction on PostgreSQL 12+, but the new label cannot be *referenced* in that same transaction
  (`55P04 unsafe_new_enum_value_usage`). Supabase wraps each migration file in one transaction, so a
  single file that adds `SUPER_ADMIN` and then compares against it fails. Split into
  `0052_super_admin_role.sql` (the `ALTER TYPE` alone) and
  `0053_backend_security_and_correctness_fixes.sql` (everything else). There is no prior `ALTER TYPE`
  anywhere in `supabase/migrations/`, so this path is untested in the repo.
- **Decision**: add `SUPER_ADMIN`; update `is_super_admin()` — which exists and currently can never
  return true — to compare against the new label; purge dead `PRIEST` references from SQL and edge
  guards.
- **[CORRECTED] `AGENTS.md` itself hardcodes the dead role.** Line 31 states admin routes must require
  `ADMIN|PRIEST|SUPER_ADMIN`; purging `PRIEST` requires amending that invariant, not just the code.
- **Alternatives considered**: keep `PRIEST` as an ADMIN alias (rejected — unused roles create
  ambiguity, and 0033 already collapsed them).

---

## R8: Concurrency and negative-authorization testing

- **[CORRECTED] `dblink` is available but not installed**; `pg_background` is **not available at all**
  in this image. The first draft's Technical Context listed `dblink` as an existing dependency. The
  concurrency suite runs `CREATE EXTENSION IF NOT EXISTS dblink;` itself (test scripts execute as
  `postgres`), and `EXECUTE` on `dblink` functions stays restricted to `postgres` — it is a privileged
  outbound-connection primitive and must never reach `anon` or `authenticated`.
- **Decision**: real multi-session tests for (1) two simultaneous `book_slot` calls on a slot with one
  seat left, (2) `apply_payment` racing `expire_stale_bookings` on the same booking, (3) concurrent
  `claim_event_outbox_batch` proving `SKIP LOCKED` prevents double delivery. Negative-authorization
  assertions for every hardened function and every revoked table grant.
- **[CORRECTED] This collides with an `AGENTS.md` invariant.** Line 33 requires unauthorized
  `UPDATE`/`DELETE` tests to assert **0 rows affected, not exceptions**. That rule is correct for
  RLS-level denial, but table-level `REVOKE` raises `42501 insufficient_privilege` — an exception is
  the only observable outcome. The invariant needs an explicit carve-out for grant-level denial,
  otherwise 007's own tests violate the constitution they are checked against.
- **Rationale**: the two existing "concurrency" suites run sequentially in a single session and prove
  nothing about races; the absence of a negative-authorization test for `apply_payment` is precisely
  why the anon grant survived this long.
- **Alternatives considered**: mock-only unit tests (rejected — cannot exercise locking or grants).

---

## R9: Making the verification gates genuinely runnable

- **[CORRECTED] `/tests` is not mounted inside `supabase_db_church`.** Any gate of the form
  `docker exec … psql -f /tests/<file>` fails. Suites must be piped over stdin
  (`docker exec -i … psql … < supabase/tests/<file>`). `run_all.sql` cannot be used over stdin either,
  because its `\ir` paths do not resolve, and it has CRLF endings so `\r` must be stripped from any
  extracted filename.
- **Decision**: add a minimal root `package.json` declaring only `@supabase/supabase-js` so
  `node supabase/e2e/book_pay_flow.mjs` can run; document how to **start** (not merely check) the
  `supabase_edge_runtime_church` container; document the placeholder Paymob env values the Arabic
  sweep needs; note that the e2e script additionally requires staging Paymob and `TEST_*` secrets
  supplied out of band and never committed.
- **Session shell is bash**, not PowerShell — quickstart commands are written accordingly.

---

## R10: In-place migration edits with no forward path

- **Finding**: commit `f663168` (already on `main`) edited `0043_faq_categories.sql` and
  `0044_storage_buckets.sql` in place. `0051_storage_objects_rls_guard.sql` forward-migrates only the
  `storage.objects` RLS enable, so `supabase db push` environments are missing the rest.
- **Decision**: re-apply the remainder idempotently inside 0053 — 12 storage policies gaining
  `TO authenticated` (one also gaining `AND public.is_admin()`), and for `faq_categories` the
  `tenant_id` default change to `public.tenant_id()`, the admin policy's `TO authenticated` plus
  tenant predicate, the public read policy's `TO anon, authenticated`, and the replacement of
  `GRANT ALL` with granular `GRANT INSERT, UPDATE, DELETE`.
- **Wider finding, documented but not remediated**: at least eleven commits on `main` edited
  already-numbered migrations in place, touching `0001`, `0002`, `0013`, `0016`, and `0039`–`0048`
  (`4559dc9`, `74f5681`, `9354b66`, `7e0ee01`, `0da91fb`, `5a49583`, `f663168`, `f773831`, `01b0ffa`,
  `e3c529d`, `652647f`). Reconstructing every forward path is out of scope; 007 records that
  `supabase db reset` is currently the only reliable route to a known-good schema, and adds the
  `AGENTS.md` carve-out for objects the migration role does not own (`storage.objects`, per the
  guarded idiom already used by 0048 and 0051).
- **Also documented, not changed** (handoff decision 23): `tenant_id()` falls back to a hardcoded
  `'1'` and `handle_new_user()` inserts a literal `tenant_id = 1`. Harmless with one tenant; recorded
  explicitly as multi-tenant scaffolding that is **not** a completed capability.
