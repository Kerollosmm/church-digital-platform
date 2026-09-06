# Feature Specification: Backend Security and Correctness Fixes

**Feature Branch**: `007-backend-security-fixes`

**Created**: 2026-08-17

**Status**: Reviewed — every schema reference below verified against the live `supabase_db_church`
database on 2026-08-17

**Input**: User description: "Execute backend security hardening and correctness remediation based on 2026-08-17 audit findings and architectural decisions: (1) enforce RPC-only writes on sensitive tables (payments, complaints, users, audit_log, roles_permissions) and revoke direct DML; (2) restrict anon-callable SECURITY DEFINER functions including apply_payment, expire_stale_bookings, promote_waiting_list, and materialize_analytics; (3) cleanly remove video catalog and personal video delivery assets/endpoints following the product pivot; (4) restore SUPER_ADMIN in app_role and purge dead role references; (5) eliminate service_slots.remaining_capacity counter drift in favor of dynamic calculation from active bookings and consolidate book_slot overloads; (6) fix reconciliation edge function error handling to prevent premature failure marking; (7) implement stuck outbox row reaping and staff resend capability; (8) add real multi-session concurrency and negative-authorization test suites."

## Clarifications & Decisions

Binding architectural decisions from the 2026-08-17 technical audit, the 007/008 planning handoff, and
live schema verification.

- **RPC-Only Write Boundary**: Direct client `INSERT/UPDATE/DELETE` on `payments`, `complaints`,
  `users`, `audit_log`, and `roles_permissions` is revoked. `p0_admin_all` is dropped from the four
  tables that carry it — and because it is the **only** policy on `payments`, `audit_log`, and
  `roles_permissions`, replacement admin `SELECT` policies are created in the same migration.
  `users` has no `p0_admin_all`; only its grants change.
- **Privilege Hardening**: five `SECURITY DEFINER` functions still at PostgreSQL's default
  `EXECUTE TO PUBLIC` with no internal caller check are narrowed: `apply_payment(bigint)`,
  `expire_stale_bookings()`, `promote_waiting_list(bigint)`, `materialize_analytics()`, and
  `rbac_allows(app_role, text, text)`. Functions that already guard internally
  (`decrypt_complaint`, `emergency_override`, `cancel_booking`, `confirm_booking`,
  `complete_booking`, `join_waiting_list`, `manual_book`) and the read-only
  `active_booking_count` are explicitly **out of scope**.
- **Video Machinery Pivot**: total removal — `videos`, `video_purchases`, `payments.video_id`,
  `purchase_video`, `apply_video_payment`, `deliver_personal_video`, the `youtube-expiry` and
  `deliver-personal-video` edge functions, the live `youtube-expiry` pg_cron job, the `video_ready`
  outbox template, and the client code in **both** the mobile and the admin app. Both tables verified
  empty, so no data migration.
- **Role Alignment**: add `SUPER_ADMIN` to `app_role`; make `is_super_admin()` — which currently can
  never return true — compare against it; purge obsolete `PRIEST` references from SQL, edge guards,
  and the `AGENTS.md` invariant that hardcodes them.
- **Dynamic Slot Capacity**: `v_available_slots` **already** derives availability dynamically from
  `active_booking_count` and already carries `security_invoker=true` and a tenant predicate. The work
  is to delete the redundant `service_slots.remaining_capacity` counter and its **three** writers, and
  to pin the view's existing column contract with a regression test. The view is not rewritten.
- **Reconciliation Resilience**: `reconcile-payments` treats non-2xx and timeouts as transient — log
  and continue — and reserves `mark_payment_failed` for explicit terminal gateway verdicts.
- **Outbox Recovery & Visibility**: the current `event_outbox` cannot support a reaper — it has no
  claim timestamp and no error column. Two columns are added, the claim RPC stamps one of them, and a
  reaper plus an admin read surface and resend RPC are introduced. The staff UI is deferred to
  feature 008.
- **Test Invariants**: genuine multi-session concurrency tests over `dblink`, plus negative
  authorization assertions for every hardened function and revoked grant. New suites use pgTAP; the
  42 pre-existing suites keep their plain-assert style but must still compile against the new schema.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Secure Financial & Audit Integrity (Priority: P1)

Parishioners, staff, and church leadership rely on the system to protect financial records and audit
histories against unauthorized tampering. Under the hardened architecture, direct database
manipulation on sensitive tables is blocked from every client session — including admin sessions,
which today can set `payments.status = 'PAID'`, read `complaints.body_encrypted` raw instead of
through the Vault-audited decryption RPC, and edit or delete `audit_log` rows. Every state transition
must pass through an audited server-side procedure with an explicit privilege grant.

**Why this priority**: core security foundation. Prevents illegitimate payment confirmations,
un-audited access to encrypted complaint bodies, and destruction of the audit trail.

**Independent Test**: attempt direct DML as `authenticated` and as `anon` across all five tables — all
rejected with `insufficient_privilege`. Invoke `apply_payment` and `rbac_allows` with the anon key —
both refused. Confirm an admin session still *reads* payments, audit log, and roles/permissions.

**Acceptance Scenarios**:

1. **Given** any client session including an admin one, **When** attempting a direct `UPDATE`,
   `INSERT`, or `DELETE` on `payments`, `complaints`, `users`, `audit_log`, or `roles_permissions`,
   **Then** PostgreSQL refuses with `42501 insufficient_privilege`. Grant-level denial produces an
   exception, not a zero-row result — a distinction the test suite asserts explicitly.
2. **Given** an unauthenticated request to `/rest/v1/rpc/apply_payment`, **When** dispatched with any
   payment id, **Then** it is refused. (Today it succeeds: `apply_payment` is PUBLIC-executable with
   no caller check, and `payments.id` is a sequential `bigint`.)
3. **Given** the Paymob webhook or the reconciliation cron running under `service_role`, **When**
   invoking `apply_payment(p_payment_id)`, **Then** the payment transitions to `PAID`, a
   `PENDING_PAYMENT` booking moves to `AWAITING_CALL`, and exactly one `booking_confirmed` outbox row
   is written.
4. **Given** an admin browsing complaints, **When** listing them, **Then** the list is served by
   `v_complaints` and the raw `complaints` table is unreadable directly, so encrypted bodies can only
   be revealed through `decrypt_complaint`.
5. **Given** an admin opening the payments screen, **When** the list loads, **Then** rows are returned
   — proving the replacement `SELECT` policy was created alongside the `p0_admin_all` drop.
6. **Given** an anon session, **When** calling `rbac_allows`, **Then** it is refused, so the RBAC
   matrix is no longer enumerable by unauthenticated callers.

---

### User Story 2 - Accurate Slot Capacity Without Counter Drift (Priority: P1)

A parishioner booking liturgy or confession slots must see accurate availability. The reservation view
already computes availability from live booking rows, but a redundant `service_slots.remaining_capacity`
counter is maintained in parallel by three separate functions and can diverge from reality. This
feature deletes the counter and its writers, leaving a single source of truth, and consolidates the two
`book_slot` overloads into one procedure that locks the slot row before testing capacity.

**Why this priority**: two competing capacity numbers is the bug class. Removing the counter removes
the possibility of phantom seats, overbooking, or false full-capacity lockouts.

**Independent Test**: run genuine concurrent bookings against a slot with one seat left and confirm
exactly one succeeds; cancel and re-check availability; confirm no object in the database still
references `remaining_capacity`; confirm `v_available_slots` still exposes its original column names.

**Acceptance Scenarios**:

1. **Given** a slot with capacity 20 and 5 active bookings, **When** availability is queried,
   **Then** `available_seats` is 15, derived from `active_booking_count`.
2. **Given** an active booking, **When** it is cancelled — whether by the parishioner, by staff, or by
   the expiry sweep, all of which land on status `CANCELLED` — **Then** availability increases by 1
   with no counter adjustment anywhere. (`booking_status` has no `EXPIRED` and no `REFUNDED` label;
   `REFUNDED` is a *payment* status reached via `mark_payment_refunded`, and refunding does not by
   itself change booking status or capacity.)
3. **Given** two concurrent reservation attempts for the final seat, **When** processed
   simultaneously, **Then** exactly one succeeds and the other raises `SLOT_FULL`, serialised by
   `SELECT capacity ... FOR UPDATE` on the slot row.
4. **Given** the expiry sweep running while a payment is being settled, **When** both target the same
   booking, **Then** `FOR UPDATE SKIP LOCKED` causes the sweep to skip the booking rather than cancel
   a paid one. The deadline column is `bookings.locked_until`.
5. **Given** the last seat is taken, **When** the booking commits, **Then** the same `SLOT_EXHAUSTED`
   realtime notification previously emitted by the depletion trigger is emitted from `book_slot`, so
   subscribed clients see no behavioural change.
6. **Given** the mobile slot grid and the admin manual-booking screen, **When** they query
   `v_available_slots`, **Then** they continue to receive `slot_id, service_id, title_ar, starts_at,
   ends_at, capacity, price, location, booked_count, available_seats, slot_status` unchanged.

---

### User Story 3 - Clean Pivot & Decommissioning of Obsolete Video Machinery (Priority: P2)

Following the decision to discontinue the video catalog and personal video delivery in favour of Event
Booking Extra Services, all video structures, endpoints, scheduled jobs, and UI modules are removed.

**Why this priority**: eliminates the YouTube token-refresh maintenance burden and the associated
attack surface before feature 008 adds new capability.

**Independent Test**: no video tables, columns, or RPCs remain; the `youtube-expiry` cron job is gone
from `cron.job`; both Flutter apps build and their test suites pass with no video references.

**Acceptance Scenarios**:

1. **Given** the updated schema, **When** inspecting tables and routines, **Then** `videos`,
   `video_purchases`, `payments.video_id`, `purchase_video`, `apply_video_payment`, and
   `deliver_personal_video` are absent.
2. **Given** the outbox dispatcher, **When** processing the queue, **Then** no `video_ready` handler
   remains and `event_outbox_whatsapp_template_check` no longer permits that template. The remaining
   allow-list is `booking_confirmed, payment_received, booking_cancelled, booking_rescheduled,
   booking_apology, otp_auth, booking_payment_received, booking_offer` — no `payment_receipt` template
   exists and none is introduced.
3. **Given** the scheduled jobs table, **When** inspected, **Then** no job POSTs to
   `/functions/v1/youtube-expiry`. Left in place it would fire daily at a dead endpoint.
4. **Given** the mobile app, **When** navigating, **Then** the video purchase workflow and all its
   entry points are gone from the router, home hub, bottom navigation, strings, and error mapper.
5. **Given** the **admin** app, **When** navigating, **Then** the video management screen — which
   performs `from('videos').insert(...)` and would fail at runtime once the table is dropped — is gone
   along with its route and test.

---

### User Story 4 - Resilient Background Dispatch & Processing Recovery (Priority: P2)

Church administrators need assurance that outbound notifications are delivered. If a worker dies
mid-dispatch, the item is stranded in `PROCESSING` forever, because nothing re-enqueues it. This
feature adds the schema needed to detect that, a scheduled reaper, and an admin read surface plus a
resend procedure.

**Why this priority**: prevents silently lost parishioner communications from transient worker failures.

**Independent Test**: insert a row stuck in `PROCESSING` with an old claim timestamp and run the reaper
— it returns to `PENDING` with incremented attempts, or parks as `FAILED` when already at the attempt
ceiling. Invoke the resend RPC as an admin and as a non-admin.

**Acceptance Scenarios**:

1. **Given** the outbox schema, **When** a row is claimed, **Then** a claim timestamp is recorded, and
   **when** a dispatch fails, **then** the failure reason is recorded — neither of which the current
   table can store.
2. **Given** a row in `PROCESSING` whose claim is older than the timeout, **When** the reaper runs,
   **Then** it returns to `PENDING` with `attempts + 1`, `next_attempt_at = now()`, and the claim
   timestamp cleared.
3. **Given** such a row already at the maximum of 5 attempts, **When** the reaper runs, **Then** it is
   parked as `FAILED` with an explanatory reason rather than incremented — an unconditional increment
   would violate the existing attempts check constraint and abort the whole reaper run.
4. **Given** failed dispatches, **When** an admin queries the failure read surface, **Then** each row
   is shown with its handler type, attempts, timestamps, failure reason, and recipient/template
   details; and non-admins receive nothing.
5. **Given** an admin resending a failed dispatch, **When** confirmed, **Then** the row returns to
   `PENDING` with attempts reset to 0, the failure reason cleared, and the claim timestamp cleared. A
   non-admin caller is refused with `FORBIDDEN`; an unknown id yields `EVENT_NOT_FOUND`.

---

### User Story 5 - Explicit Administrative Roles & Permission Hierarchy (Priority: P3)

Governance requires a distinction between administrators and super-administrators, and removal of the
deprecated role that no longer maps to anything.

**Why this priority**: `is_super_admin()` exists today and can never return true, so any code path
gated on it is dead. `PRIEST` was collapsed away by migration 0033 but references survive.

**Independent Test**: `is_super_admin()` evaluates true for a super-admin and false for a standard
admin; no `PRIEST` reference remains in SQL, edge guards, or documented invariants.

**Acceptance Scenarios**:

1. **Given** a user with the `SUPER_ADMIN` role, **When** `is_super_admin()` is evaluated, **Then** it
   returns true.
2. **Given** a standard `ADMIN`, **When** attempting a super-admin-only action, **Then** it is refused
   with the frozen `FORBIDDEN` contract.
3. **Given** the enum change, **When** the migrations are applied, **Then** the label is added by a
   migration that does nothing else, because PostgreSQL forbids referencing a newly added enum label in
   the transaction that adds it and Supabase wraps each migration file in a single transaction.
4. **Given** the role invariants recorded in `AGENTS.md`, **When** `PRIEST` is purged from the code,
   **Then** the invariant text is amended in the same change, since it currently hardcodes the dead
   role as a required admin-route check.

---

### User Story 6 - Fault-Tolerant Payment Reconciliation Sweeps (Priority: P3)

When the reconciliation sweep verifies pending payments against Paymob, temporary network faults, 5xx
responses, or timeouts must not cancel valid payments. Today any non-2xx marks the payment `FAILED`,
and because the sweep only re-selects `CREATED` rows, a parishioner who genuinely paid is stranded
permanently with no booking.

**Why this priority**: protects paying parishioners from losing a booking to a gateway blip.

**Independent Test**: mock 502 and timeout responses and verify the payment stays `CREATED`; mock an
explicit terminal decline and verify it transitions to failed.

**Acceptance Scenarios**:

1. **Given** a payment in `CREATED`, **When** the gateway returns 5xx or times out, **Then** the
   worker logs the payment id and status and leaves the record untouched for the next sweep.
2. **Given** a payment in `CREATED`, **When** the gateway definitively reports cancellation or
   rejection, **Then** it transitions to failed.
3. **Given** the checkout function, **When** it boots without valid Paymob secrets — absent, empty, or
   the placeholder string `"0"` that two of them currently default to — **Then** it fails fast rather
   than silently producing invalid checkout URLs.
4. **Given** the two cron-driven functions, **When** an unauthenticated caller POSTs to them, **Then**
   they return the frozen Arabic `401 UNAUTHORIZED` body. Both currently accept any caller; the
   existing pg_cron jobs already send the service-role bearer token, so no cron change is needed.

---

### Edge Cases

- **Concurrent slot reservation at the capacity boundary**: row-level locking on the slot serialises
  validation so exactly one transaction wins.
- **Concurrent settlement and expiration**: `FOR UPDATE SKIP LOCKED` in the expiry sweep skips a
  booking currently being settled instead of cancelling it.
- **Worker crash between outbox claim and acknowledgment**: the row stays `PROCESSING` until the reaper
  interval elapses, then returns to `PENDING` — unless it has already reached the attempts ceiling, in
  which case it is parked as `FAILED` rather than incremented past the constraint limit.
- **Dropping the only policy on a table**: revoking DML and dropping `p0_admin_all` from `payments`,
  `audit_log`, and `roles_permissions` removes admin `SELECT` too unless replacement policies land in
  the same migration. `audit_log` and `roles_permissions` have no `tenant_id` column, so their policies
  must not carry a tenant predicate.
- **Newly added enum label used in the same transaction**: raises `55P04`; handled by splitting the
  migration.
- **External image references in the content backlog**: seeded priest photos are absolute
  `https://images.unsplash.com/...` URLs, so they are permanent false positives, while priest photos
  that *are* in storage get reported twice. The backlog query is restricted to internal storage paths.
- **Payment gateway secret defaults**: startup validation halts the function rather than letting it run
  with `"0"` placeholders. This interacts with the local Arabic-error verification gate, which
  therefore requires non-`"0"` placeholder values in the local env file rather than a weakened check.
- **Legacy test suites referencing a dropped column**: nine existing suites read `remaining_capacity`,
  `available_seats`, or `slot_status`. They keep their plain-assert style but must be updated to
  compile.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST revoke direct `INSERT`, `UPDATE`, and `DELETE` on `payments`,
  `complaints`, `users`, `audit_log`, and `roles_permissions` from `anon` and `authenticated`,
  retaining `SELECT`, and route all mutations through privilege-restricted `SECURITY DEFINER` RPCs.
- **FR-001a**: The system MUST drop the permissive `p0_admin_all` policy from `payments`, `complaints`,
  `audit_log`, and `roles_permissions`, **and in the same migration** create explicit admin `SELECT`
  policies for `payments`, `audit_log`, and `roles_permissions`, since `p0_admin_all` is their only
  policy. The tenant predicate MUST be omitted where no `tenant_id` column exists.
- **FR-002**: The system MUST restrict execution on `apply_payment(bigint)`,
  `expire_stale_bookings()`, `promote_waiting_list(bigint)`, `materialize_analytics()`, and
  `rbac_allows(app_role, text, text)` via `REVOKE ALL FROM PUBLIC, anon, authenticated` plus narrow
  grants. Signatures MUST match the live catalog exactly; a `REVOKE` naming a non-existent signature
  aborts the migration. `active_booking_count` and the seven internally guarded functions MUST be left
  unchanged.
- **FR-003**: The system MUST remove every video artefact: tables `videos` and `video_purchases`,
  column `payments.video_id`, routines `purchase_video`, `apply_video_payment`,
  `deliver_personal_video`, edge functions `youtube-expiry` and `deliver-personal-video`, the
  `video_ready` outbox template and its dispatcher handler, and the client code in **both** the mobile
  app and the admin app.
- **FR-003a**: The system MUST unschedule the live `youtube-expiry` pg_cron job in the same migration
  that deletes the function.
- **FR-004**: The system MUST add `SUPER_ADMIN` to `app_role`, update `is_super_admin()` to compare
  against it, and purge deprecated `PRIEST` references from policies, routines, and edge guards.
- **FR-004a**: The enum label MUST be added by a migration that contains nothing else, because the
  label cannot be referenced in the transaction that adds it.
- **FR-005**: The system MUST delete `service_slots.remaining_capacity` together with **all three**
  objects that read or write it — the cancel-restore trigger function, the depletion-broadcast trigger
  function, and the atomic-booking helper. `v_available_slots` already derives availability dynamically
  and MUST NOT be rewritten; its column contract MUST be pinned by a regression test.
- **FR-005a**: The `SLOT_EXHAUSTED` realtime notification currently emitted by the depletion trigger
  MUST be preserved by emitting an identical payload from `book_slot` when the post-insert active count
  reaches capacity.
- **FR-006**: The system MUST consolidate both `book_slot` overloads into a single canonical procedure
  that locks the slot row before testing capacity. The WhatsApp opt-in parameter MUST keep its existing
  name, because the mobile client invokes the RPC with named arguments and a test asserts the exact
  argument map. The quantity parameter is dropped; seat count is fixed at 1.
- **FR-007**: `expire_stale_bookings` MUST select candidates with `FOR UPDATE SKIP LOCKED` on
  `status = 'PENDING_PAYMENT' AND locked_until < now()`, and MUST continue to transition to
  `CANCELLED` — the booking status enum has no `EXPIRED` label.
- **FR-008**: The system MUST add the outbox columns required to detect a stranded claim and to record
  a failure reason, MUST stamp the claim timestamp inside the existing claim RPC, and MUST provide a
  scheduled reaper that returns timed-out rows to `PENDING` — or parks them as `FAILED` when already at
  the attempts ceiling, so the existing attempts check constraint is never violated.
- **FR-009**: The system MUST provide an admin-only read surface for failed dispatches, created with
  `security_invoker = true` so it cannot become an RLS bypass, plus an `is_admin()`-guarded resend
  procedure. The staff-facing UI is explicitly out of scope for this feature.
- **FR-010**: The reconciliation worker MUST treat non-2xx responses and timeouts as transient — log
  the payment id and status and continue — and MUST reserve the failure transition for explicit
  terminal gateway verdicts.
- **FR-011**: `event-dispatcher` and `reconcile-payments` MUST authenticate the inbound bearer token
  against the cron/service secret using a constant-time comparison and return the frozen Arabic
  `401 UNAUTHORIZED` body on mismatch. `paymob-checkout` MUST validate its four Paymob secrets at
  module scope and refuse to boot if any is absent, empty, or `"0"`. No new error codes are introduced.
- **FR-012**: `v_content_backlog` MUST restrict its priest-photo branch to internal storage paths and
  exclude rows already covered by the storage-objects branch, so external URLs are neither flagged as
  missing nor double-counted.
- **FR-013**: All database changes MUST be packaged as new forward migrations with the new test suites
  registered in the SQL test runner. No already-numbered migration may be edited.
- **FR-013a**: The system MUST re-apply idempotently the changes that a previous in-place edit made to
  the FAQ-categories and storage-buckets migrations, since environments upgraded with `db push` never
  received them. The broader in-place-edit history is documented rather than remediated, and
  `supabase db reset` is recorded as the only reliable route to a known-good schema.
- **FR-014**: The test suite MUST include genuine multi-session concurrency tests — two simultaneous
  bookings on a one-seat slot, settlement racing the expiry sweep, and concurrent outbox claims proving
  no double delivery. `dblink` is available but not installed, so the suite MUST install it, and
  `EXECUTE` on its functions MUST NOT be granted to `anon` or `authenticated`.
- **FR-015**: The test suite MUST include negative authorization assertions for every hardened function
  and every revoked grant. Because table-level revocation raises `42501 insufficient_privilege`, these
  assertions check for an exception; the documented invariant requiring "0 rows affected, not
  exceptions" applies to RLS-level denial and MUST be amended with an explicit carve-out for
  grant-level denial.
- **FR-016**: The nine existing test suites that reference the dropped capacity column or the view's
  column names MUST be updated so the full suite still compiles and passes.
- **FR-017**: The single-tenant scaffolding MUST be documented explicitly rather than left implicit:
  the tenant resolver falls back to a hardcoded value and the new-user trigger inserts a literal tenant
  id. This is recorded as incomplete multi-tenant groundwork, not a delivered capability, and is not
  changed by this feature.

### Key Entities *(include if feature involves data)*

- **Service Slot Availability**: the existing view deriving `available_seats` as
  `GREATEST(capacity - active_booking_count(slot), 0)` with a `slot_status` of `AVAILABLE`, `BOOKED`,
  or `CLOSED`. After this feature it is the *only* representation of capacity; the parallel counter
  column is gone.
- **Hardened Payment Record**: mutable only by `service_role` through `apply_payment`,
  `mark_payment_failed`, and `mark_payment_refunded`. It has no `user_id`, so there is no
  parishioner-facing read path; admin-only `SELECT` is the least-privilege choice.
- **Audit Log Entry**: written by triggers and `SECURITY DEFINER` routines, readable by admins,
  no longer modifiable or deletable by any client. Has no `tenant_id` column.
- **Outbox Task State**: a queue item with status `PENDING`, `PROCESSING`, `COMPLETED`, or `FAILED`,
  an `attempts` counter bounded to 0–5 by a check constraint, a next-attempt timestamp, and — added by
  this feature — a claim timestamp and a last-error string.
- **Application Role**: `USER`, `ADMIN`, `SUPER_ADMIN`. `PRIEST` is not a member and its residual
  references are removed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of direct client `INSERT`, `UPDATE`, and `DELETE` attempts on the five sensitive
  tables fail with `42501 insufficient_privilege`, including from admin sessions.
- **SC-002**: 100% of attempts to invoke the five hardened routines from the anon or authenticated keys
  are refused, while the service-role callers continue to succeed.
- **SC-003**: Admin reads on `payments`, `audit_log`, and `roles_permissions` continue to return rows
  after the policy replacement, and the admin payments screen renders.
- **SC-004**: Slot availability matches the live active booking count across booking, cancellation, and
  expiry, with no database object referencing the dropped counter column.
- **SC-005**: 0 video tables, columns, routines, edge functions, scheduled jobs, or client references
  remain, across both Flutter apps.
- **SC-006**: 100% of simulated transient gateway errors leave the payment in `CREATED`.
- **SC-007**: 100% of outbox rows stranded in `PROCESSING` beyond the timeout are recovered or parked,
  and the reaper never aborts on an attempts-ceiling row.
- **SC-008**: Unauthenticated POSTs to the two cron-driven functions return `401` with the frozen
  Arabic body.
- **SC-009**: The full SQL suite — including the two new suites and the nine updated legacy suites —
  and the Deno suite pass with 0 failures, and a clean `supabase db reset` applies both migrations
  without `55P04`.
- **SC-010**: `v_available_slots` still exposes its original eleven columns, so no client or widget
  test regresses.

## Assumptions

- **Single Church Deployment**: the platform serves one community. Multi-tenant scaffolding remains
  internal and incomplete — see FR-017 — and is not surfaced in any interface.
- **Financial Precision**: monetary values remain integer piastres (1 EGP = 100).
- **Paymob Gateway Exclusive**: Paymob remains the only online gateway; its webhook remains the sole
  authority that marks an online payment paid, and no client writes payment status.
- **Event Booking Scope Boundary**: Event Booking with Extra Services — venue scheduling, configurable
  add-ons, price snapshots, cash receipting — plus the staff outbox backlog UI and the clean
  architecture rework land in feature 008 on top of this foundation.
- **Package Management for Testing**: a minimal root package declaration is added solely so the
  existing end-to-end script can resolve its client library. Real Paymob staging and `TEST_*` secrets
  are supplied out of band and never committed.
- **Superseded Specifications**: `specs/005-admin-domain-layer` and `specs/006-mobile-domain-layer`
  are superseded by the 007/008 split and are removed.
