# AUTONOMOUS AGENT DISPATCH PROMPT: CHURCH DIGITAL PLATFORM FULL IMPLEMENTATION

════════════════════════════════════════════════════════════════════════════════
SECTION 1: IDENTITY, ENVIRONMENT, SCOPE & STOP BOUNDARY
════════════════════════════════════════════════════════════════════════════════
You are the Principal Software & Database Architect autonomous agent for repo `C:\church` (Windows, PowerShell/Bash).
Your mission: Execute full end-to-end implementation and stabilization for the Church Digital Platform (Single Egyptian Coptic Church):
  1. Implement Spec 008 (Event Booking with Extra Services) schema, RPCs, and pgTAP test suites.
  2. Harden Deno Edge Functions auth/webhook perimeters and zero-leak contracts.
  3. Implement Flutter Mobile (`apps/mobile/`) and Flutter Web Admin (`apps/admin/`) event booking domain layers, state blocs, and UI workflows.
  4. Run and pass 100% test suites across SQL (`node scripts/test-sql.js`), Deno (`deno test`), and Flutter (`flutter test`).
STOP when all 4 phases pass their automated verification gates with raw proof logs provided in the final report.

════════════════════════════════════════════════════════════════════════════════
SECTION 2: ORDERED SOURCE OF TRUTH (READ FIRST)
════════════════════════════════════════════════════════════════════════════════
READ FIRST in exact order before modifying any files:
1. `AGENTS.md` & `docs/superpowers/plans/conventions.md` — Locked Architectural Invariants, RLS rules, RPC security, financial boundaries.
2. `memory-bank/event-booking-pivot.md` — 25 Binding Decisions for Event Booking with Extra Services.
3. `memory-bank/systemPatterns.md` & `memory-bank/activeContext.md` — Active system state, migration head (`0063`), and verification scripts.
4. `supabase/migrations/0063_service_role_grants_and_payment_rpc.sql` — Existing migration style and RPC patterns.
5. `supabase/tests/run_all.sql` — Test runner registry for pgTAP suites.

════════════════════════════════════════════════════════════════════════════════
SECTION 3: VERIFIED FACTS & REVIEWER FINDINGS (DO NOT RE-LITIGATE)
════════════════════════════════════════════════════════════════════════════════
F1. [Baseline Head]: Migration head is `0063_service_role_grants_and_payment_rpc.sql`. All 54 prior SQL test suites (`0001`–`0063`) pass 100% via `node scripts/test-sql.js`.
F2. [Video System Purged]: All `videos`, `video_purchases`, and video RPCs are decommissioned. Never re-introduce them.
F3. [Financial Boundary]: Direct client DML on `public.payments` is strictly revoked. All payments use `SECURITY DEFINER` RPCs (`record_booking_payment`, `apply_payment`, `admin_record_cash_payment`, `mark_payment_refunded`). `apply_payment` is `service_role` ONLY.
F4. [Currency Standard]: All monetary values in database, RPCs, Edge Functions, and Flutter models MUST be stored and computed in **integer piastres** (`1 EGP = 100 piastres`). Zero floating-point calculations.
F5. [Double-Booking Prevention]: Venue/altar scheduling MUST enforce PostgreSQL exclusion constraints on `(resource_id, tstzrange)` using `btree_gist` extension at database engine level.
F6. [Review-First Lifecycle]: Event bookings follow `SUBMITTED -> CONFIRMED / REJECTED -> PENDING_PAYMENT -> PAID / PARTIALLY_PAID -> COMPLETED`. No payment is accepted on unconfirmed requests.
F7. [Slot Booking Lifecycle]: Sacraments/trips follow `PENDING_PAYMENT -> AWAITING_CALL -> CONFIRMED -> COMPLETED` with atomic `SELECT ... FOR UPDATE` in `book_slot()`.
F8. [RBAC & Permissions]: Roles are `USER`, `ADMIN`, `SUPER_ADMIN`. All `PRIEST` role references are purged. Admin endpoints require non-null admin role and 2FA PIN verification.
F9. [Arabic Error Contract]: Client-facing errors use `{"error": "<CODE>", "message_ar": "..."}` with codes `UNAUTHORIZED | FORBIDDEN | BAD_REQUEST | UPSTREAM_ERROR | INTERNAL`. Edge functions fail closed without raw exception leakage.

════════════════════════════════════════════════════════════════════════════════
SECTION 4: PHASED EXECUTION TASKS (STRICT TDD & VERIFICATION)
════════════════════════════════════════════════════════════════════════════════

────────────────────────────────────────────────────────────────────────────────
PHASE A: DATABASE ENGINE & SPEC 008 (EVENT BOOKING WITH EXTRAS)
────────────────────────────────────────────────────────────────────────────────
Execute tasks with strict RED -> GREEN -> VERIFY -> COMMIT cadence:

Task A1 (RED Test): Create `supabase/tests/0064_event_booking_schema_test.sql`
- Use pgTAP skeleton: `\set ON_ERROR_STOP on`, `CREATE EXTENSION IF NOT EXISTS pgtap;`, `BEGIN;`, `SELECT no_plan();`
- Assert existence and column types of tables: `venues_resources`, `event_types`, `extra_services`, `event_type_extra_services`, `booking_extra_services`, `event_resource_bookings`, `payment_audit_logs`.
- Assert `btree_gist` exclusion constraint prevents overlapping active booking ranges on the same `resource_id`.
- Assert RLS is enabled on all 7 tables and anonymous users cannot insert/update.
- Register test in `supabase/tests/run_all.sql` with `\ir 0064_event_booking_schema_test.sql`.
- Run `node scripts/test-sql.js` -> MUST FAIL (RED).

Task A2 (GREEN Migration): Create `supabase/migrations/0064_event_booking_schema.sql`
- Run `CREATE EXTENSION IF NOT EXISTS btree_gist;`
- Extend `booking_status` enum with `'SUBMITTED'`, `'REJECTED'`, `'PARTIALLY_PAID'` if not present.
- Create all 7 tables with `tenant_id BIGINT NOT NULL DEFAULT public.tenant_id()`.
- Add foreign keys and exclusion constraint:
  `EXCLUDE USING gist (resource_id WITH =, booking_period WITH &&) WHERE (is_active = true)`
- Enable RLS on all tables and create granular policies (`public.is_admin()`, user ownership, tenant filter).
- Grant sequence usage: `GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;`
- Run `node scripts/test-sql.js` -> MUST PASS (GREEN). Commit: `feat(sql): 0064 event booking schema with exclusion constraints`.

Task A3 (RED Test): Create `supabase/tests/0065_event_booking_rpcs_test.sql`
- Assert `submit_event_booking`:
  - Inserts booking in `SUBMITTED` state.
  - Correctly computes total price in piastres and snapshots into `booking_extra_services`.
  - Enqueues `EVENT_SUBMISSION_RECEIVED` into `whatsapp_outbox`.
- Assert `admin_confirm_booking`:
  - Unprivileged role execution is DENIED (`throws_ok`).
  - Admin allocates venue resource, transitions booking to `PENDING_PAYMENT`.
  - Collision on same venue/time raises exclusion error.
  - Enqueues `EVENT_BOOKING_CONFIRMED` outbox item with breakdown and payment link.
- Assert `admin_reject_booking`:
  - Fails if `rejection_reason` is empty or whitespace.
  - Transitions booking to `REJECTED`, logs audit, enqueues `EVENT_BOOKING_REJECTED`.
- Assert `admin_record_cash_payment`:
  - Admin/SuperAdmin inserts cash payment row (`status = 'PAID'`).
  - Creates immutable ledger row in `payment_audit_logs`.
  - Updates `paid_price_piastres` and transitions booking to `PAID` or `PARTIALLY_PAID`.
- Register test in `supabase/tests/run_all.sql`.
- Run `node scripts/test-sql.js` -> MUST FAIL (RED).

Task A4 (GREEN Migration): Create `supabase/migrations/0065_event_booking_rpcs.sql`
- Implement `submit_event_booking(p_event_type_id bigint, p_requested_time timestamptz, p_extras jsonb, p_notes text) RETURNS bigint`.
- Implement `admin_confirm_booking(p_booking_id bigint, p_venue_id bigint, p_confirmed_start timestamptz, p_duration_minutes int) RETURNS void`.
- Implement `admin_reject_booking(p_booking_id bigint, p_rejection_reason text) RETURNS void`.
- Implement `admin_record_cash_payment(p_booking_id bigint, p_amount_piastres bigint, p_receipt_ref text, p_notes text) RETURNS bigint`.
- Implement SuperAdmin configuration RPCs (`superadmin_upsert_event_type`, `superadmin_upsert_extra_service`, `superadmin_upsert_venue`).
- Harden privileges: `REVOKE ALL` from PUBLIC/anon/authenticated on admin functions, grant only to authenticated with `is_admin()` check inside.
- Run `node scripts/test-sql.js` -> MUST PASS (GREEN). Commit: `feat(sql): 0065 event booking rpcs and outbox triggers`.

────────────────────────────────────────────────────────────────────────────────
PHASE B: DENO EDGE FUNCTIONS HARDENING & TESTS
────────────────────────────────────────────────────────────────────────────────
Task B1: Edge Function Contracts & Tests
- In `supabase/functions/paymob-checkout/index.ts`:
  - Enforce Bearer token verification.
  - Fetch booking amount directly from PostgreSQL via service client in integer piastres.
  - Handle upstream Paymob API failures with try/catch returning 502 `UPSTREAM_ERROR` in standard Arabic contract `{"error": "UPSTREAM_ERROR", "message_ar": "..."}`.
- In `supabase/functions/paymob-webhook/index.ts`:
  - Verify HMAC SHA-512 in constant-time.
  - Advance payment status via `apply_payment(p_payment_id)` or `record_booking_payment`.
  - Enforce idempotency on duplicate `PAID` delivery.
- In `supabase/functions/event-dispatcher/index.ts`:
  - Drain outbox batches with `FOR UPDATE SKIP LOCKED`.
  - Map outbox event payloads for `EVENT_SUBMISSION_RECEIVED`, `EVENT_BOOKING_CONFIRMED`, `EVENT_BOOKING_REJECTED`, and `EVENT_PAYMENT_RECEIVED` to Meta WhatsApp API templates.
- Run `deno test --allow-env --allow-net supabase/functions/` -> ALL UNIT TESTS MUST PASS. Commit: `feat(functions): hardened checkout, webhook, and outbox dispatcher`.

────────────────────────────────────────────────────────────────────────────────
PHASE C: FLUTTER MOBILE APP (`apps/mobile/`)
────────────────────────────────────────────────────────────────────────────────
Task C1: Event Booking Feature Layer
- Implement `apps/mobile/lib/features/events/`:
  - Models: `EventType`, `ExtraService`, `EventBooking`, `BookingExtraService`.
  - Repository: `EventBookingRepository` calling `submit_event_booking` RPC and querying views with Arabic error parsing.
  - State: `EventBookingBloc` managing selected extras, quantity increments, live total price calculation in piastres/EGP, and submission state.
  - Screens:
    - `EventCatalogScreen`: List of available church events (Marriage, Baptism, Engagement, Funerals).
    - `EventBookingScreen`: Date picker, preferred slot time, dynamic add-on checklist with instant price calculation.
    - `EventBookingDetailScreen`: Timeline status tracking (`SUBMITTED -> CONFIRMED -> PENDING_PAYMENT -> PAID`), venue assignment display, and online checkout button.
- Startup check: Assert non-empty `SUPABASE_ANON_KEY` in `main.dart`.
- Localization: Arabic RTL formatting, EGP display strings.
- Tests: Add unit and widget tests in `apps/mobile/test/features/events/`.
- Verification: Run `flutter analyze` (0 errors) and `flutter test` (100% pass). Commit: `feat(mobile): event booking with extra services feature`.

────────────────────────────────────────────────────────────────────────────────
PHASE D: FLUTTER WEB ADMIN APP (`apps/admin/`)
────────────────────────────────────────────────────────────────────────────────
Task D1: Event Management & Review Desk
- Implement `apps/admin/lib/features/events_management/`:
  - Repository: Administrative RPC calls (`admin_confirm_booking`, `admin_reject_booking`, `admin_record_cash_payment`, `superadmin_manage_*`).
  - State: `EventReviewBloc`, `EventConfigBloc`.
  - Screens:
    - `EventBookingsQueueScreen`: Filterable queue by status (`SUBMITTED`, `PENDING_PAYMENT`, `CONFIRMED`, `COMPLETED`, `REJECTED`).
    - `EventReviewDialog`: Venue resource selector, schedule picker, confirmation trigger.
    - `EventRejectDialog`: Required rejection reason input field with validation.
    - `RecordCashPaymentModal`: Amount in EGP (converted to piastres), receipt reference, notes.
    - `EventConfigScreen`: SuperAdmin venue and extra service management.
- Auth Guards: Enforce `ADMIN` or `SUPER_ADMIN` role check and PIN validation.
- Tests: Add unit and widget tests in `apps/admin/test/features/events_management/`.
- Verification: Run `flutter analyze` (0 errors) and `flutter test` (100% pass). Commit: `feat(admin): event booking review desk and cash receipt recording`.

════════════════════════════════════════════════════════════════════════════════
SECTION 5: HARD RULES, PROHIBITIONS & EVIDENCE CONTRACT
════════════════════════════════════════════════════════════════════════════════

HARD PROHIBITIONS (Instant Reject If Violated):
- NEVER edit or modify historical migrations `0001` through `0063`. Forward migrations `0064` and `0065` only.
- NEVER use `GRANT ALL` or grant direct table DML to `anon` or `public`.
- NEVER use floating-point numbers for currency amounts. Piastres integer only.
- NEVER allow client direct DML on `public.payments` or `public.payment_audit_logs`.
- NEVER bypass test-first TDD: write and run failing RED test before writing migration/code.
- NEVER summarize test results. Final report MUST paste raw terminal output.

FINAL REPORT FORMAT:
1. Executive Summary: List of implemented features, migrations (`0064`, `0065`), and screens.
2. Git Commits Table: Hash, commit message, files changed.
3. Verification Gate Outputs (PASTE RAW TERMINAL OUTPUT):
   - `node scripts/test-sql.js` (Must show all suites passing, 0 failures).
   - `deno test --allow-env --allow-net supabase/functions/` (Must show all tests passing).
   - `cd apps/mobile && flutter analyze && flutter test` (Must show 0 analysis issues and all tests passing).
   - `cd apps/admin && flutter analyze && flutter test` (Must show 0 analysis issues and all tests passing).
4. Unresolved Issues / Deviations: State `None` or document any out-of-band constraints.
