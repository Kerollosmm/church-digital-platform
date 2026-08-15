# Church Digital Platform — Real-World Project Plan (Supabase Architecture)

> **For agentic workers:** This is the master project blueprint. Each phase gets its own detailed implementation plan (TDD, bite-sized tasks) in this folder. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a complete digital platform for a single Egyptian Coptic church: parishioner app + admin dashboard + booking/payment engine (Paymob) + WhatsApp automation + paid video access + analytics.

**Architecture:** **Supabase** as the platform backbone — managed PostgreSQL (single source of truth, ACID), Supabase Auth (phone OTP), PostgREST API + Row Level Security (RLS), Realtime for live booking status, Edge Functions (Deno) for integrations (Paymob webhooks, WhatsApp Cloud API, FCM, YouTube expiry), pg_cron for scheduled jobs (lock expiry, reconciliation, analytics materialization). One Flutter mobile app (parishioners) and one Flutter Web/PWA admin dashboard talk directly to Supabase via `supabase_flutter`; RLS is the security boundary. No custom API server to build or maintain.

**Tech Stack:**
- Mobile + Admin UI: Flutter (iOS/Android) + Flutter Web (PWA dashboard)
- Platform: Supabase (PostgreSQL 16 + Auth + Realtime + Storage + Edge Functions + pg_cron)
- Backend logic: SQL (views, RPCs, triggers) + Deno/TypeScript Edge Functions
- Payments: Paymob Accept API + webhooks (Vodafone Cash, wallets, Fawry, Meeza, cards)
- Messaging: WhatsApp Cloud API (Meta approved templates only, explicit opt-in)
- Video: YouTube unlisted uploads (recorded events, no live streaming) + link delivery via WhatsApp
- Auth: Supabase phone OTP (Twilio or custom Egyptian SMS provider; WhatsApp OTP template fallback)
- Push: Firebase Cloud Messaging (announcements, reminders)
- Infra: Supabase cloud (Free tier → Pro $25/mo), no VPS to run

---

## 1. Locked Decisions (supersede the original Arabic spec where they differ)

| # | Decision | Rationale |
|---|----------|-----------|
| A1 | **No YouTube live streaming.** Events recorded, uploaded as **unlisted** videos, link sold via Paymob + WhatsApp | Original spec's live-stream quota claim was technically wrong; recorded-video flow needs almost zero YouTube API quota |
| A2 | YouTube **unlisted**, never **private** | Private videos can't be shared by link; unlisted = "pay → get link" works |
| A3 | YouTube channel needs **phone verification once** (for >15 min uploads) — NOT multi-day live-stream verification | Live streaming not needed |
| A4 | **Supabase replaces the custom NestJS/Redis/VPS backend** | No Redis available → slot locks via Postgres `SELECT FOR UPDATE` + active-booking count vs capacity (no unique index — it broke multi-seat slots). Cuts ~half the backend work, built-in auth/backups/monitoring |
| A5 | Realistic timeline: MVP ≈ **6 weeks** (end of Phase 1), full platform ≈ **7 weeks** (2-3 devs) | External dependencies (Paymob, Meta templates, Play review) run parallel |
| A6 | Team: 2-3 devs (1 backend/SQL + Edge Functions, 1-2 Flutter). Budget: $20-40/mo | Locked assumptions |
| A7 | **Single church** (multi-church deferred, but `tenant_id` column designed from day 1) | Cheap now, painful to retrofit |
| A8 | Booking slot lock = **20 minutes**, stored in `bookings.locked_until` + `SELECT FOR UPDATE` row lock in `book_slot()`; "retry payment for same booking" button | Egypt OTP/mobile network realities; no Redis needed |
| A9 | Every WhatsApp message uses **Meta approved templates + recorded opt-in** at booking time | Anti-ban compliance, non-negotiable |
| A10 | **All state transitions go through SECURITY DEFINER SQL RPCs** (`book_slot`, `confirm_booking`, `cancel_booking`, `emergency_override`…), never raw table writes | RLS can't be bypassed; state machine enforced in DB |
| A11 | Edge Functions hold secrets (Paymob HMAC key, Meta token, Google OAuth2 client/refresh token); never in the app. COMPLAINTS_KEY lives in Supabase Vault (in-DB pgp_sym_encrypt, 0026) | Security boundary |
| A12 | **Roles: `PARISHIONER`, `PRIEST`, `ADMIN`, `SUPER_ADMIN`** — no SERVANT role (member registry/visitation out of scope) | Core platform only; CMeeting replacement excluded |

## 2. Scope — Final Modules

- **M1 — Info & Complaints Portal:** masses/psalms/services schedule, priests directory & confession/visitation hours, encrypted complaints box (routed to assigned priest/admin), FAQ, location & contact.
- **M2 — Booking Engine (events & funerals):** interactive availability calendar, 20-min lock during payment, waiting list with auto-promotion, live booking status (PENDING_PAYMENT / AWAITING_CALL / CONFIRMED / COMPLETED / CANCELLED / RESCHEDULED), payment webhook race handling (payment on stale/cancelled booking → REFUND_PENDING + enqueue refund_requests), manual booking mode (cash, by employee), priest **Emergency Override** (reschedule + auto apology via WhatsApp + refund or new slot).
- **M3 — Paid Video Access:** customer buys an event recording → Paymob charge → webhook → WhatsApp template with **unlisted YouTube link**. Optional expiry job (privacy update/delete after N days). Sale makes **zero** YouTube API calls.
- **M5 — Core Analytics & Reports:** slot utilization per service, payment reports (paid/refunded totals), booking trends (volume + status mix). Dashboard screens + CSV export for admin/priest.
- **X0 — Cross-cutting:** phone OTP auth, RLS-based RBAC (4 roles), FCM push (announcements), audit log, WhatsApp outbox automation, Arabic-first UI.

**Explicitly out of scope (deferred, not planned):** CMeeting replacement (members/households registry, visitation assignments, QR attendance, irregular-attendance alerts, offline-first Drift SQLite sync), live streaming, multi-church.

## 3. Architecture

```
┌───────────────────┐   ┌───────────────────┐
│ Flutter Mobile    │   │ Flutter Web/PWA   │
│ (parishioners)    │   │ (admin dashboard) │
│                   │   │  employees only   │
└─────────┬─────────┘   └─────────┬─────────┘
          │ supabase_flutter SDK  │ (anon key + JWT; RLS is the security boundary)
          ▼                       ▼
┌────────────────────────────────────────────────────────────────┐
│                     SUPABASE (cloud)                          │
│  Auth (phone OTP) · PostgREST (tables/views/RPCs) · Realtime  │
│  PostgreSQL 16 + RLS · pg_cron · Storage (files)              │
│  Edge Functions (Deno):                                       │
│   ├─ paymob-webhook     └─ whatsapp-sender   └─ fcm-push      │
│   ├─ reconcile-payments └─ youtube-expiry    └─ otp-sms       │
└──────┬──────────────────┬──────────────────────┬──────────────┘
       │                  │                      │
       ▼                  ▼                      ▼
┌─────────────┐   ┌──────────────┐   ┌─────────────────────┐
│   Paymob    │   │ WhatsApp     │   │ YouTube (upload)    │
│  Accept API │   │ Cloud API    │   │ + FCM push service  │
└─────────────┘   └──────────────┘   └─────────────────────┘
```

**Key principles:**
- Apps never hold secrets — only Supabase anon key + user JWT. All money/WhatsApp logic runs in Edge Functions or SECURITY DEFINER RPCs.
- Business logic lives in **SQL** (constraints, triggers, RPCs, views) — the source of truth stays transactional; Edge Functions handle external HTTP (Paymob, Meta, YouTube, FCM).
- Scheduled work via **pg_cron** (lock expiry every minute, nightly reconciliation, analytics materialization, WhatsApp outbox drain, video expiry).

## 4. Tech Decisions (ADR-style)

| Decision | Chosen | Alternatives rejected | Why |
|----------|--------|----------------------|-----|
| Platform | **Supabase cloud** | Custom NestJS + VPS, Firebase | Built-in auth/Postgres/backups/realtime/monitoring; open source → self-host escape hatch; fits 2-3 dev team |
| Auth | Supabase phone OTP (Twilio/custom SMS provider webhook) + WhatsApp OTP template fallback | Email/password, custom OTP server | Egyptian users have phones; no password reset burden |
| Slot locking | Postgres: `SELECT FOR UPDATE` on slot + active-booking count vs `capacity` + `locked_until` + pg_cron expiry | Redis (not available), advisory locks, unique partial index (breaks capacity > 1) | Zero extra infra; row lock serializes capacity-accurately; Transaction Pooler (6543) for peak load |
| Payments | Paymob Accept + webhook → Edge Function | Fawry API only, Vodafone direct | Only option covering Vodafone Cash + Fawry + Meeza + cards in one integration |
| Messaging | WhatsApp Cloud API via Edge Function + outbox table (retry/backoff) | Twilio WhatsApp ($$), unofficial libs (ban risk) | Official, cheap, template-safe |
| Video | YouTube unlisted + link | Self-hosting (bandwidth $), Vimeo ($$) | Free unlimited storage; link = access |
| Push | FCM via Edge Function | In-app polling | Free, required for announcements |
| Scheduled jobs | pg_cron (+ pg_net to trigger Edge Functions) | External cron (VPS) | Runs inside Supabase, no extra infra |
| Realtime | Supabase Realtime (booking status → admin dashboard) | Polling | Live dashboard, free tier covers it |
| Flutter state | Riverpod + go_router + supabase_flutter (direct connection, no offline layer) | Bloc, dio+auth manually, drift SQLite offline queue | SDK handles auth/realtime/postgrest; offline sync out of scope (A12) |
| Infra | Supabase Free tier → Pro ($25/mo); region **Frankfurt** (closest to Egypt) | VPS | $20-40/mo budget; zero ops |

**Multi-church later:** every root table carries `tenant_id`; RLS policies filter on it from day 1.

## 5. Data Model (core entities — full DDL lives in Phase 0 plan migrations)

```sql
users               (auth.users managed by Supabase + public.users profile: phone, name, role, tenant_id, fcm_token)
roles_permissions   (role, resource, action)                       -- RBAC matrix for RLS checks
priests             (id, name, photo_url, bio, visitation_hours)
services            (id, title_ar, description, schedule, location, tenant_id)
service_slots       (id, service_id, starts_at, ends_at, capacity, price, status)
bookings            (id, slot_id, user_id, status, paid_amount, payment_ref, locked_until,
                     created_by[system|employee], notes, tenant_id)
payments            (id, booking_id, gateway_ref, amount, status, raw_webhook JSONB, created_at)
refund_requests     (id, payment_id, booking_id, amount, reason, status[PENDING|SUBMITTED|COMPLETED|FAILED], created_at)
waiting_list        (id, slot_id, user_id, position, status, created_at)
videos              (id, title_ar, event_date, yt_url, price, privacy, expires_after_days, uploaded_by)
video_purchases     (id, video_id, user_id, payment_id, access_granted_at, link_sent_at)
complaints          (id, user_id, category, body_encrypted, status, assigned_to, tenant_id)
announcements       (id, title_ar, body_ar, target_role, published_at, tenant_id)
audit_log           (id, user_id, action, entity_type, entity_id, meta JSONB, created_at)
whatsapp_outbox     (id, phone, template_name, params JSONB, status, attempts, next_attempt_at)
whatsapp_optins     (phone, consented_at, source)
event_outbox        (id, handler_type[WHATSAPP|PAYMOB_REFUND|FCM_PUSH], payload JSONB, status, attempts, max_attempts, next_attempt_at) -- 0027 unified outbox
fcm_tokens          (update_fcm_token RPC on public.users.fcm_token + 0029 FCM status triggers)
realtime_pub        (0031 ALTER PUBLICATION supabase_realtime ADD TABLE public.bookings, public.service_slots)
admin_pins          (user_id PK ref public.users, pin_hash, attempts, locked_until) -- 0034 admin 3-step PIN
```

- Slot lock (A8): `book_slot()` does `SELECT * FROM service_slots WHERE id = p_slot_id FOR UPDATE`, counts active bookings (`PENDING_PAYMENT|AWAITING_CALL|CONFIRMED`) against `capacity`, and raises `SLOT_FULL`/`ALREADY_BOOKED_SLOT`/`TOO_MANY_ACTIVE_BOOKINGS`. No unique partial index (it capped every slot at 1 booking).
- All tables: `tenant_id` + timestamps + soft-delete flag.
- Complaints body: encrypted in-DB via pgp_sym_encrypt + Vault key COMPLAINTS_KEY (0026).
- Phase 2 adds analytics tables only: `slot_utilization_monthly`, `payments_monthly`, `bookings_monthly` (no new source tables).

## 6. Booking & Payment State Machine

```
                    ┌──────────────────────┐
  book_slot() ────► │ PENDING_PAYMENT      │── locked_until = now()+20min
  (FOR UPDATE lock) │ (capacity counted)   │
                    └─────────┬────────────┘
                              │ Paymob webhook PAID
                              ▼
                    ┌──────────────────────┐
   priest/staff ───►│ AWAITING_CALL        │──(funerals: confirm details by phone)
                    └─────────┬────────────┘
                              │ confirm_booking()
                              ▼
                    ┌──────────────────────┐
                    │ CONFIRMED            │──► COMPLETED (event passed)
                    └─────────┬────────────┘
                              │ emergency_override()
                              ▼
                    RESCHEDULED / CANCELLED (+refund via Paymob edge fn, +WhatsApp apology)

  Payment webhook race (apply_payment on stale/CANCELLED booking):
    ──► payment_status = REFUND_PENDING + enqueue refund_requests (never grant seat)
```

- pg_cron every minute: `PENDING_PAYMENT` with `locked_until < now()` → CANCELLED (frees slot) → promote waiting-list position 1 (reservation row with 10-min take-it window) → WhatsApp offer.
- Every transition: one SQL RPC + `audit_log` row + (customer-facing) WhatsApp outbox row.
- Nightly reconciliation: Edge Function queries Paymob for stale PENDING_PAYMENT older than 24h, resolves mismatches.

## 7. External Dependencies — Critical Path (START NOW, parallel to all coding)

| Dependency | Action needed | Lead time | Owner |
|-----------|---------------|-----------|-------|
| Paymob merchant account (under church charity association) | KYC documents, bank account, onboarding | 1-4 weeks | Church admin + dev |
| Meta Business Manager + WhatsApp Business Account | Business verification, phone, test number | 2-7 days | Dev |
| WhatsApp **template submissions** | booking_confirmed, payment_received({{1}}=link), cancelled, rescheduled, apology, otp (+ booking_payment_received, booking_offer) | 3-14 days/round | Dev |
| YouTube channel phone verification | One-time; needed for >15 min uploads | Minutes-hours | Media team |
| Google Play Console ($25) | Account setup | 1-5 days | Dev |
| Supabase project | Sign up, create org + project (region: Frankfurt) | 1 day | Dev |
| SMS provider for OTP | Twilio trial/paid or Egyptian aggregator (webhook custom provider) | 1-3 days | Dev |
| Domain + DNS | e.g. church-name-eg.org | 1 day | Church admin |

## 8. Roadmap — 7 Weeks (2-3 devs)

### Phase 0 — Foundations & Onboarding (Weeks 1-2)
- [ ] External onboarding kickoff (§7 checklist, weekly review ritual)
- [ ] Supabase project + supabase CLI local stack (`supabase start`), GitHub monorepo + CI (lint, flutter test, SQL lint, edge function deploy)
- [ ] Migrations: full schema (§5), RLS baseline policies, RBAC seed (4 roles × 9 resources), audit trigger, pg_cron jobs skeleton
- [ ] Auth wiring: phone OTP configured (Twilio/custom provider), Flutter apps scaffolded with supabase_flutter, login screens both apps
- [ ] **DoD:** `supabase start` runs locally; schema migrated; RLS smoke tests pass; login works end-to-end in staging

### Phase 1 — MVP: Portal + Booking + Payments + WhatsApp + Paid Videos (Weeks 3-6)
- **W3:** M1 portal (services/priests/FAQ read views + complaints submit/decrypt via pgp_sym_encrypt in-DB (0026) + announcements)
- **W4:** M2 booking core: `book_slot` RPC (atomic lock), availability view, booking mgmt admin screens, state machine RPCs + audit + lock-expiry cron
- **W5:** Paymob: checkout creation edge fn, `paymob-webhook` (HMAC, idempotent), payments table flow, reconciliation job; admin dashboard bookings screens
- **W6:** WhatsApp: outbox table + `whatsapp-sender` edge fn + template registry + opt-in at booking; waiting list + auto-promotion; manual booking; refund + Emergency Override + auto-apology; M3 videos (purchase flow, link delivery, expiry job); mobile booking flow + status UI; hardening + e2e (book→pay→confirm→WhatsApp mock) + Play internal testing
- [ ] **DoD:** Parishioner: see schedule → book → pay Vodafone Cash → confirmation + video link on WhatsApp. Employee: manual book, override, refund. Admin dashboard live in staging.

### Phase 2 — Analytics & Hardening (Week 7)
- **W7:** Nightly materialization (pg_cron → analytics tables: slot utilization, payments, booking trends); admin dashboard screens (fl_chart) + CSV export via edge fn; hardening (analytics RLS penetration, concurrency + webhook regression re-runs); ops runbook (backups verified, restore drill, template change process); final project DoD + handover
- [ ] **DoD:** Priest answers "which slots are underutilized", "how are payments/refunds trending", "how do bookings look this month" in <1 min from the dashboard.

## 9. Infrastructure & Running Costs ($5-30/mo)

| Item | Choice | Cost |
|------|--------|------|
| Supabase | **Free tier** (500 MB DB, 50k MAU, 5 GB egress, 500k edge invocations) — enough for a single church at launch | $0 |
| Supabase Pro (optional, when needed: PITR, more bandwidth) | $25/mo | $0-25 |
| SMS OTP | Twilio (~$0.04/OTP) or local aggregator; target <500 OTPs/mo | $5-10/mo |
| WhatsApp Cloud API | Free 1,000 conversations/mo; ~$0.01-0.02/msg after | $5-20/mo |
| Domain + Play | ~$12/yr + $25 one-time | ~$3/mo amortized |
| **Total** | | **~$10-30/mo** |

No VPS, no Docker to run in production, no Redis. Backups/monitoring built into Supabase. Video never touches our infra (YouTube).

## 10. Testing Strategy

- **SQL/RLS tests (psql DO-blocks in CI):** RLS policies per role (parishioner sees own data only; priest/admin per matrix), slot-lock behavior (FOR UPDATE + capacity count; multi-seat slots accept capacity bookings, then SLOT_FULL), state machine RPCs, audit trigger, analytics views admin-only
- **Edge Function tests (Deno + mocks):** Paymob HMAC verification + idempotency, WhatsApp outbox retry/backoff, refund, YouTube expiry (OAuth2 token exchange + bearer update)
- **Flutter widget tests:** booking flow, status chips, portal screens, complaints form
- **E2E (staging):** book → pay (Paymob sandbox) → webhook → confirm → WhatsApp (test number); manual book → emergency override → apology + refund
- **Load smoke:** 100 concurrent `book_slot` on one slot — exactly one succeeds (FOR UPDATE lock proof)
- **Security:** OTP rate limits, RLS penetration attempts per role, complaints ciphertext never returned by PostgREST

## 11. Security & Compliance

- **RLS is the enforcement layer** — every table has policies; PostgREST bypass is impossible without JWT
- Auth: Supabase OTP with rate limiting; short-lived access JWT + refresh (Supabase handles rotation)
- Paymob webhook: HMAC signature verified in Edge Function; replay protection (transaction_id uniqueness)
- Complaints: encrypted in-DB via pgp_sym_encrypt + Vault key COMPLAINTS_KEY (0026)
- Audit log: trigger-based on all state transitions + payment events
- Egyptian personal data law: consent checkbox at registration, export/delete endpoints, data residency (EU region), privacy policy page
- Edge Function secrets in Supabase secrets manager (`supabase secrets set`), never in apps or git

## 12. Budget Summary (startup)

| Item | One-time | Monthly |
|------|----------|---------|
| Supabase | $0 | $0 (Free) → $25 (Pro) |
| SMS + WhatsApp overage | — | $10-30 |
| Play ($25) + domain (~$12/yr) | ~$37 | — |
| Apple developer (deferred) | $99 | — |
| Paymob transaction fees | — | ~1-3% pass-through |

## 13. Top Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| RLS misconfiguration leaks data | Medium | RLS tests in CI, policy review checklist before each release, no `SELECT *` in views |
| Meta rejects WhatsApp templates | Medium | Submit Phase 0, multiple variants, test-number testing first |
| Paymob onboarding slow (church paperwork) | Medium | Start day 1; sandbox until then; manual booking mode as real-money fallback |
| OTP delivery failure in Egypt | Medium | WhatsApp OTP template first, SMS fallback, retry payment button, 20-min lock |
| Supabase lock-in / pricing change | Low | Open source; self-host path documented (same schema/migrations); data always portable |
| Unlisted video link leaked | Low-Med | Acceptable at church scale; optional expiry job (private/delete after N days) |
| Emergency funeral collides with booked slot | Certain (eventually) | Emergency Override + apology template + refund, built in Phase 1 |
| Twilio SMS blocked/delayed in Egypt | Medium | Custom SMS provider webhook support in Supabase; WhatsApp OTP primary |
| Scope creep (multi-church, live streaming, member registry) | Medium | Locked A1/A7/A12; defer beyond week 7 |

## 14. Team & Responsibilities

| Role | Focus |
|------|-------|
| Backend/full-stack dev (1) | SQL schema + RLS + RPCs + Edge Functions (Paymob/WhatsApp/FCM/YouTube), pg_cron, CI, security |
| Flutter dev (1-2) | Mobile + PWA apps, booking flows, Realtime subscriptions, analytics charts |
| Church liaison | External onboarding docs, content (schedule, priests, FAQ), template approvals, acceptance testing, media team uploads |

## 15. Definition of Done (project-level)

- [ ] Parishioner completes book → pay → confirm → (video link) journey with real money
- [ ] Employee manual booking + priest emergency override + refunds verified in production
- [ ] Complaints: encrypted at rest, decrypted only by assigned priest/admin
- [ ] Analytics dashboard answers the 3 operational questions in §8 Phase 2 in <1 min
- [ ] Runbook exists: restore drill executed, template-change process documented
- [ ] Data-protection basics live: consent, export, delete, encrypted complaints, audit log

## 16. Open Questions (resolve before Phase 1 starts)

1. Which charity association entity holds the Paymob account (owner of paperwork)?
2. Which church committee member owns external onboarding follow-ups?
3. Video pricing: flat fee or donation tiers? Refund policy wording for the WhatsApp template?
4. SMS provider: Twilio vs local Egyptian aggregator — test delivery on Vodafone/Etisalat/Orange?
5. Supabase Free vs Pro at launch — decision after Phase 0 staging load check

---

*Next step: each phase plan in this folder (2026-08-05-phase0-foundations.md, 2026-08-05-phase1-mvp.md, 2026-08-05-phase2-analytics.md) implements this blueprint task-by-task with TDD.*
