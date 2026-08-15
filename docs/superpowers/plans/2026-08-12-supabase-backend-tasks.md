# Supabase Backend Sub-Project Task Breakdown (`supabase/`)

**Target Directory:** `C:\church\supabase`  
**Stack:** PostgreSQL 17 + RLS + SECURITY DEFINER RPCs + Deno 2 Edge Functions + pg_cron + Vault + pgcrypto

---

## 1. Database & Migrations Module (`supabase/migrations/`)

- [x] **Task 1: Core Schema & Extensions Baseline (`0001`–`0003`)**
  - Enable `pgcrypto`, `pg_cron`, `pg_net`, `supabase_vault`.
  - Create enums (`app_role`, `booking_status`, `payment_status`, `video_privacy`, `complaint_status`, `outbox_status`).
  - Create core tables (`users`, `roles_permissions`, `services`, `service_slots`, `bookings`, `payments`, `videos`, `complaints`).
  - Seed initial RBAC permissions table.

- [x] **Task 2: RLS Policies Baseline (`0002`, `0011`)**
  - Enable RLS on all public tables (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY`).
  - Add user row isolation policies (`auth.uid() = user_id`) and admin access policies (`is_admin_or_priest()`).

- [x] **Task 3: Booking State Machine & Lock Engine (`0008`, `0010`, `0015`, `0017`)**
  - RPC `book_slot()`: `SELECT ... FOR UPDATE` capacity check + 20-min PENDING_PAYMENT lock.
  - RPC `cancel_booking()`: Release seat and transition booking status.
  - RPC `reschedule_booking()`: Atomic slot transfer with lock guard.
  - RPC `manual_book()`: Admin manual booking override.
  - RPC `emergency_override()`: Priest/Admin emergency slot displacement and refund enqueue.
  - Cron `lock-expiry-cleanup`: Cancel expired pending locks every minute.

- [x] **Task 4: Payments & Webhook Security (`0012`, `0013`, `0028`)**
  - RPC `apply_payment()`: Idempotent payment application, handle stale payment race condition by queueing refund requests (`REFUND_PENDING`).
  - Cron `reconcile-pending-payments`: Reconcile pending Paymob transactions older than 30 mins.

- [x] **Task 5: Security & Outbox Architecture (`0024`, `0026`, `0027`, `0029`, `0031`)**
  - RPC `transition_booking_status()`: Single-writer transition engine for booking state updates.
  - RPC `encrypt_complaint()` / `decrypt_complaint()`: PGP asymmetric encryption for parishioner complaints.
  - Table `event_outbox`: Unified queue for `WHATSAPP`, `PAYMOB_REFUND`, `FCM_PUSH`, and `SMS`.
  - Triggers on status transitions enqueuing FCM push notifications.
  - Publication `supabase_realtime`: Add `bookings` and `service_slots` for live admin dashboard.

- [x] **Task 6: Docker-Free Offline-First Sync (`0032_offline_sync.sql`)**
  - Table `offline_sync_log`: Mutation idempotency log with strict RLS policies.
  - RPC `sync_offline_mutations(p_mutations jsonb)`: Transactional SECURITY DEFINER batch sync handler.

---

## 2. Deno 2 Edge Functions Module (`supabase/functions/`)

- [x] **Task 7: Paymob Checkout & Webhook Integration (`paymob-checkout`, `paymob-webhook`)**
  - `paymob-checkout`: Generate Paymob authentication token, order ID, and payment key iframe token.
  - `paymob-webhook`: Verify HMAC-SHA512 signature from Paymob query parameters, execute `apply_payment()` RPC.

- [x] **Task 8: Unified Event Dispatcher (`event-dispatcher`)**
  - Batch drain `event_outbox` (100 rows/run, 10 parallel concurrency).
  - Integrations: Meta WhatsApp Graph API v20.0, Paymob Refund API, Google FCM v1 HTTP API (OAuth2 service account token exchange).

- [x] **Task 9: Analytics & YouTube Maintenance (`analytics-export`, `youtube-expiry`)**
  - `analytics-export`: Stream CSV downloads, sanitize formula injection characters (`=`, `+`, `-`, `@`), support ISO date filtering.
  - `youtube-expiry`: Exchange Google OAuth2 refresh token for bearer token, set expired video access to unlisted via YouTube API v3.

- [x] **Task 10: Local Docker-Free Offline Sync Function (`offline-sync`)**
  - Deno 2 starter Edge Function handling CORS, JWT authorization forwarding, and invoking `sync_offline_mutations` RPC.

---

## 3. Backend Verification & CI Protocol

- [ ] **Task 11: SQL Test Suite Execution**
  - Run all pgTAP/psql migration tests against cloud/local DB instance:
    `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0001_init_schema_test.sql`

- [ ] **Task 12: Deno Edge Function Unit Tests**
  - Execute Deno test runner across all function directories:
    `deno test --allow-env supabase/functions/`

- [ ] **Task 13: Cloud Deployment Execution**
  - Link Supabase CLI: `npx supabase link --project-ref <your-ref>`
  - Push DB migrations: `npx supabase db push`
  - Deploy Edge Functions: `npx supabase functions deploy`
