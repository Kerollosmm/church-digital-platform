# Project Conventions — Shared Across All Phase Plans (Supabase)

Locked conventions for the Church Digital Platform. Every phase plan MUST follow these exactly. When in doubt, check the master plan: `docs/superpowers/plans/2026-08-05-church-digital-platform.md`.

## Repository Layout (monorepo, root = C:\church)

```
apps/
  mobile/     Flutter app (parishioners, Android first, iOS later)
  admin/      Flutter Web PWA (employees, priests, super admins)
supabase/
  migrations/          (0001_init.sql, 0002_..., ordered timestamped SQL files)
  functions/           (Edge Functions, one folder each)
    paymob-webhook/    index.ts
    whatsapp-sender/   index.ts
    reconcile-payments/ index.ts
    fcm-push/          index.ts
    otp-sms/           index.ts (optional custom SMS provider)
  seed/                (seed.sql — RBAC matrix, demo content)
  config.toml          (supabase CLI local config)
docs/
  superpowers/plans/   (all plan documents)
.github/workflows/     (CI)
```

## Supabase CLI Workflow

- Local dev: `supabase start` (Docker-based local stack), `supabase stop`
- Schema changes: write a new numbered migration in `supabase/migrations/` → `supabase db reset` locally → verify → `supabase db push` to staging → deploy to prod via `supabase db push --db-url $PROD_DB_URL`
- Edge Functions: `supabase functions new <name>` → `supabase functions serve` (local, with `--env-file`) → `supabase functions deploy <name> --project-ref $REF`
- Secrets: `supabase secrets set PAYMOB_HMAC_KEY=...` — NEVER in git or apps
- CI deploys: `supabase functions deploy --project-ref $REF --token $SUPABASE_ACCESS_TOKEN`

## Backend Logic Conventions (SQL first, Edge Functions for HTTP)

**Rule of thumb:** anything that touches money, bookings, or state lives in SQL (RPCs/triggers/constraints). Anything that touches the outside world (Paymob, Meta, FCM) lives in an Edge Function. PostgREST exposes:
- `GET /rest/v1/<table|view>` — reads (RLS-filtered)
- `POST /rest/v1/rpc/<function>` — state changes (SECURITY DEFINER functions)

### SQL conventions
- All state transitions are **SECURITY DEFINER** functions: `book_slot()`, `confirm_booking()`, `cancel_booking()`, `emergency_override()`, `manual_book()` … each: one transaction, writes `audit_log`, returns the new row. Apps NEVER write bookings/payments directly.
- All `SECURITY DEFINER` RPCs MUST include `SET search_path = ''` (or `SET search_path = public`) in their function signature to prevent search_path hijacking attacks.
- Audit: trigger `audit_trigger()` on bookings/payments/complaints writing to `audit_log(id, user_id, action, entity_type, entity_id, meta JSONB, created_at)`; `user_id` from `auth.uid()`.
- RLS enabled on EVERY table; policies per role using `public.users.role` (read via a `current_user_role()` SECURITY DEFINER helper).
- `tenant_id` on every business table; default via `tenant_id()` helper; policies always filter `tenant_id = tenant_id()`.
- Views for reads: `v_available_slots`, `v_my_bookings`, analytics views in Phase 2. No `SELECT *` leaks: views select explicit columns.
- Scheduled jobs: pg_cron (`cron.schedule(...)`) in migrations. Extension `pg_cron` and `pg_net` enabled. Jobs call SQL or `net.http_post` to Edge Functions.
- Idempotency: payments keyed on `gateway_ref` (unique); webhook processing is UPSERT.

### Edge Function conventions
- Deno + TypeScript, `deno.land/x/supabase` client with `SERVICE_ROLE_KEY` (server-only)
- Every function: JWT/token auth where needed, try/catch with `cors` header (Supabase functions support CORS via config), structured logging
- Unified `event_outbox` pattern: integrations enqueue rows to `public.event_outbox(id, handler_type, payload JSONB, status='PENDING', attempts=0, max_attempts=5, next_attempt_at=now())`. Handler types include `WHATSAPP`, `PAYMOB_REFUND`, `FCM_PUSH`. The `event-dispatcher` Edge Function drains the queue (100 rows/batch in parallel batches of 10), calling Meta Graph API, Paymob Refund API, or FCM v1 HTTP API (`https://fcm.googleapis.com/v1/projects/{FCM_PROJECT_ID}/messages:send` via OAuth2 service account JWT bearer token exchange with secrets `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY`), marking SENT or bumping attempts with exponential backoff (max 5). Throughput ≈ 6k msgs/hr; for latency-critical sends (OTP, confirmations) wire pg_net `net.http_post` at enqueue time.
- Paymob webhook: Paymob computes HMAC-**SHA512** (hex, lowercase) over the concatenation (no separators, booleans as lowercase `true`/`false`) of the transaction's **20 fields in this exact documented order**: `amount_cents`, `created_at`, `currency`, `error_occured`, `has_parent_transaction`, `id`, `integration_id`, `is_3d_secure`, `is_auth`, `is_capture`, `is_refunded`, `is_standalone_payment`, `is_voided`, `order.id`, `owner`, `pending`, `source_data.pan`, `source_data.sub_type`, `source_data.type`, `success`. Paymob sends the digest as the **`hmac` query parameter on the callback URL** (NOT a header); compare with constant-time equality. Replay-protect via unique `gateway_ref`, store raw body in `payments.raw_webhook`

## Enums (exact values, synced to shipped schema 2026-08-21)

Values below mirror the live database types (`pg_enum`) value-for-value.
Sync direction is DB → docs; never invent values here.

```sql
app_role               = 'USER' | 'ADMIN' | 'SUPER_ADMIN'   -- PRIEST tier deliberately removed (0060; see docs/adr/0002-video-to-event-booking-pivot.md + specs/009 US5)
booking_status         = 'PENDING_PAYMENT' | 'AWAITING_CALL' | 'CONFIRMED' | 'COMPLETED' | 'CANCELLED' | 'RESCHEDULED'
payment_status         = 'CREATED' | 'PAID' | 'FAILED' | 'REFUNDED' | 'REFUND_PENDING' | 'PENDING'
payment_channel        = 'VODAFONE_CASH' | 'INSTAPAY' | 'CASH'   -- spec 011 (ADR 0003 manual payment rail)
slot_status            = 'OPEN' | 'CLOSED'                  -- values in use (spec 009 FR-011); the view layer reports AVAILABLE|BOOKED|CLOSED
complaint_status       = 'NEW' | 'ASSIGNED' | 'RESOLVED'
event_handler_type     = 'WHATSAPP' | 'PAYMOB_REFUND' | 'FCM_PUSH' | 'SMS'
outbox_status          = 'PENDING' | 'PROCESSING' | 'SENT' | 'FAILED'
waitlist_status        = 'WAITING' | 'OFFERED'              -- values in use (spec 009 FR-011); terminal-state handling recorded as open question there
```

## Slot Locking (no Redis)

- Lock = `SELECT ... FOR UPDATE` on the `service_slots` row + counting active bookings against `capacity`; NO unique partial index (it broke multi-seat slots — capacity > 1 allowed only one booking)
- `book_slot()` raises `SLOT_FULL` / `ALREADY_BOOKED_SLOT` / `TOO_MANY_ACTIVE_BOOKINGS` (max 3 active per user — thundering-herd guard) and sets `locked_until = now() + interval '20 minutes'` for PENDING_PAYMENT
- pg_cron every minute: expired PENDING_PAYMENT → CANCELLED (frees slot) + waiting-list promotion
- Feast openings (~250-300 QPS): pool all client connections through the **Transaction Pooler (port 6543)** — session pool (5432) caps at project limit and would queue; Transaction Pooler hands each statement to a shared backend so FOR UPDATE locks serialize correctly
- Retry payment: `book:{id}:payretry` flag → a `payretry` column on bookings (v1) — recreate Paymob checkout for the SAME booking id

## External Integrations (all backend-only)

- **Paymob:** Edge Function `paymob-webhook` receives POST (HMAC-verified), upserts payments, calls `apply_payment()` SQL to transition booking; refund via `paymob-refund` logic inside `reconcile-payments` or a dedicated RPC-triggered function
- **WhatsApp:** Edge Function `whatsapp-sender` uses Meta Graph API `POST /v20.0/<phone-id>/messages` with template payloads; every send requires an opt-in row in `whatsapp_optins`; templates: `booking_confirmed`, `payment_received` ({{1}}=link), `booking_cancelled`, `booking_rescheduled`, `booking_apology`, `otp_auth`

## Auth & Security (Supabase)

- Auth provider: phone OTP (Supabase Auth). Providers: Twilio or custom SMS via webhook (`otp-sms` edge fn could call local aggregator or send WhatsApp OTP template). OTP: 6 digits, 5-min TTL, rate-limited by Supabase.
- JWT: managed by Supabase (short-lived access + refresh rotation). Read role via `auth.jwt() -> 'role'` after signing in with custom claim, or via `public.users.role` lookup helper.
- RLS: every table has policies; **never** rely on the app to filter data
- Complaints: pgp_sym_encrypt in-DB, Vault key COMPLAINTS_KEY; decryption only via decrypt_complaint() SECURITY DEFINER RPC gated to assigned priest/admin
- Throttling: PostgREST + Supabase rate limits; OTP endpoints protected by Supabase's built-in rate limits

## Flutter Conventions

- Packages: `supabase_flutter` (auth, realtime, postgrest), **Riverpod** (state), **go_router** (routing), `firebase_core` + `firebase_messaging` (FCM tokens stored on `public.users.fcm_token`). Apps connect directly to Supabase — no local SQLite/offline layer.
- Auth session: `Supabase.instance.client.auth.onAuthStateChange` → persist user + role in a Riverpod provider
- Realtime: subscribe to `bookings` changes for admin dashboard (channel `postgres_changes` filtered by tenant + table)
- Apps are Arabic-first (RTL), `flutter_localizations` + `intl`
- Widget tests: `flutter_test`; every new screen gets a smoke widget test with a mocked Supabase client

## Testing & CI

- CI (GitHub Actions): `flutter analyze` + `flutter test` (mobile, admin) → Edge Function tests (`deno test` with mocks) → SQL tests (pgTAP via `supabase db test` or a Jest script running against local `supabase start` Postgres) → `supabase functions deploy` (staging on main push)
- TDD loop per task: write failing test → run → confirm FAIL → implement minimal → run → confirm PASS → commit (conventional commits: `feat:`, `fix:`, `test:`, `chore:`)
- Commit scopes: `feat(bookings): add book_slot RPC`, `fix(payments): webhook idempotency`, `feat(mobile): booking flow screen`

## Plan Document Format (every phase plan)

```markdown
# [Phase N — Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ...
**Architecture:** ...
**Tech Stack:** ...
**Depends on:** (master plan + prior phase plan)

---

### Task N: [Name]
**Files:**
- Create: `supabase/migrations/0002_...sql`
- Test: `supabase/tests/...`

- [ ] **Step 1: Write the failing test** (full test code)
- [ ] **Step 2: Run it, expect FAIL** (exact command + expected output)
- [ ] **Step 3: Minimal implementation** (full code)
- [ ] **Step 4: Run it, expect PASS** (exact command + expected output)
- [ ] **Step 5: Commit** (exact git command)
```

## Non-Negotiables

1. No placeholders ("TBD", "implement later", "add error handling" without code). Every step shows full code.
2. Every task ends with a commit step.
3. Money/booking state transitions ONLY via SECURITY DEFINER RPCs + audit trigger — never raw table writes.
4. RLS enabled on every table; every policy tested.
5. External integrations only in Edge Functions; secrets only in `supabase secrets`.
6. Arabic-first UI; English code identifiers.
