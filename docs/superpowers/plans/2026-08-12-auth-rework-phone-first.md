# 2026-08-12 — Auth Rework: Phone-First, No-Forced-Login Model

**Status:** Approved in design chat (owner + implementer). Pending task-by-task implementation.
**Scope files:** `supabase/functions/otp-sms/`, `supabase/migrations/0034_admin_pins.sql`, `apps/mobile/`, `apps/admin/`.

---

## 1. Why this exists

User tested the app: **"nothing works"** — entering a mobile number, the OTP never arrives. Root cause is not the app UI: `signInWithOtp(phone:)` (mobile login + admin login) requires an **SMS provider configured in Supabase Auth**. Local stack (and the project) has none → OTP send fails. Conventions promised an optional custom `otp-sms` edge function — it was never built.

Second problem is UX/design: current mobile app **forces login** before anything (router redirects every route → `/login`). The church's real model (owner's intent, all decisions confirmed):

> **Identity = phone number. No passwords. No forced account. OTP is the key.**

- Parishioner opens app → **lands on church content** (announcements, services, slots) — public, no login.
- At booking time only: enter phone (+20 EG) → OTP → verified → book. Silently persists session afterwards.
- Admin signs in **every time**: phone → OTP → **memorized PIN** (set by super-admin) → dashboard.
- The same phone-first model applies to **the whole app**: my-bookings, video purchase, complaints — not just booking.

## 2. Locked decisions (A-authority, do not "fix")

| # | Decision | Detail |
|---|---|---|
| D1 | OTP channel = **WhatsApp only** | Supabase Auth **Send SMS Hook** (Standard Webhooks, signed, secret `SEND_SMS_HOOK_SECRET` = `v1,whsec_…`) → new edge function `otp-sms` → Meta WhatsApp `otp_auth` template (1 param = code). No Twilio. No SMS cost. Supabase still owns OTP generation/verification/session. |
| D2 | Admin 2nd factor = **memorized PIN** | Hashed via pgcrypto `crypt()`, per-admin, set/reset by SUPER_ADMIN. Checked after OTP. |
| D3 | User session **persists silently** | First verify creates normal Supabase session (auth.uid() based RLS untouched). No "login" screen ever shown. Re-verify only on new device/logout. |
| D4 | Keep management everything | `signInWithOtp` / `verifyOTP` client calls UNCHANGED. Only delivery channel changes server-side. `book_slot`, RLS, outbox untouched. |
| D5 | OTP lifecycle stays with Supabase Auth | 6 digits, 5-min TTL, rate limiting = Supabase built-ins. `otp-sms` only **relays** the code to WhatsApp. |

## 3. Whole-app model (applies everywhere)

```
Browse (anon, RLS public read): home hub, announcements, services, slot grid, video list
        │
        ▼  first action needing identity (book / my-bookings / buy video / complaint)
   Phone step: +20 EG number → WhatsApp OTP → verify
        │  (session created silently behind the scenes)
        ▼
   Do the thing. Session persists → next time, straight in.
   Admin web only: after OTP, extra PIN step. Every session.
```

| Screen area | Current | After |
|---|---|---|
| Mobile router | all routes → `/login` when logged out | public browsing; identity gates inline at the action |
| Booking | requires prior login | slot grid public → phone+OTP step before book → book |
| My bookings | behind login | no session → phone+OTP step → list |
| Videos | behind login | public list; phone+OTP before purchase pay |
| Complaints | (unbuilt) | phone+OTP before submit |
| Admin web | phone OTP + role check | phone OTP → role check → **PIN** → dashboard. Sign-out on every session end |

## 4. Backend work

### 4.1 New edge function `supabase/functions/otp-sms/` (Task A)

Target of Supabase Auth **Send SMS Hook** (docs: supabase.com/docs/guides/auth/auth-hooks/send-sms-hook). Configure in Auth → Settings → SMS → Send SMS Hook → URI `<project>/functions/v1/otp-sms`, secret `SEND_SMS_HOOK_SECRET` (v1,whsec_…).

- Request: signed Standard Webhooks POST (headers `webhook-id`, `webhook-timestamp`, `webhook-signature`), raw text body → verify via `Webhook` from `standardwebhooks@1.0.0` (secret = env, strip `v1,whsec_` prefix) → payload `{ user: { phone }, sms: { otp } }`.
- On verify: send WhatsApp template `otp_auth` (language `ar`, body param = `sms.otp`) via Meta Graph API `POST /v20.0/<WHATSAPP_PHONE_ID>/messages` — same mechanics/headers/body shape as `event-dispatcher` (`Authorization: Bearer WHATSAPP_TOKEN`).
- Responses: success → 200 JSON; verification failure → 401; missing otp/phone → 400; Meta API failure → 502 with JSON error incl. `http_code`/`message` (Supabase logs webhook errors).
- Env: `SEND_SMS_HOOK_SECRET`, `WHATSAPP_PHONE_ID`, `WHATSAPP_TOKEN`.
- CORS: not needed (server-to-server from Supabase Auth).
- Tests (`index_test.ts`, `deno test --allow-env`): fake `fetch` asserting exact Graph API body (template `otp_auth`, language `ar`, param = otp); valid signature passes, tampered/missing signature rejected (401); missing otp → 400; Meta non-2xx → 502.
- **TDD:** fail-test-first per phase plan discipline.

### 4.2 Migration `0034_admin_pins.sql` (Task B)

```sql
create table public.admin_pins (
  user_id uuid primary key references public.users(id) on delete cascade,
  pin_hash text not null,              -- crypt(pin, gen_salt('bf'))
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.admin_pins enable row level security;
-- no policies: SECURITY DEFINER RPCs only (matches event_outbox pattern)
```

RPCs (all SECURITY DEFINER, `is_admin()` gate where noted):

- `set_admin_pin(p_pin text)` — caller must be `is_admin()`; upsert own row; pin 4–6 digits; raises `INVALID_PIN` on format violation.
- `reset_admin_pin(p_target uuid)` — caller must be `is_super_admin()`; clears target's pin (delete row).
- `verify_admin_pin(p_pin text) returns boolean` — caller must be `is_admin()`; constant-time-ish compare via crypt; `false` when no pin set / wrong. Throttle: track failures — `attempts` + `locked_until` columns (max 5 fails / 15 min). No stub — full behavior + tests.
- `admin_pin_status() returns text` — `SET | UNSET | LOCKED` for current admin, so web app can show "set your PIN first" prompt.

RLS: enable-row-level-security BEFORE policies (they are, there are none — keep the enable statement so the checklist rule stands).

Tests (`supabase/tests/0034_admin_pins_test.sql`): fixture users (SUPER_ADMIN, ADMIN, USER) via `set local role authenticated` + jwt claims pattern from existing tests; PIN set/verify/wrong-pin/lockout/reset-by-superadmin/forbidden-for-user. `psql ... -f` → no output, exit 0.

## 5. Mobile app work (Task C)

1. **Router** (`app_router.dart`): remove forced `/login` redirect. Public routes: `/` (home hub), services list, slot grid, videos, announcements. `/login` route deleted (or kept dead only for tests — prefer delete + update tests).
2. **Phone-first gate widget**: reusable `PhoneVerifyGate` — no session → inline phone field (+20 EG) + OTP boxes (reuse `LoginScreen`/`OtpScreen` internals refactored into a shared phone-step widget) → on verify, session exists → run the child action.
   - Booking flow: tap "حجز" on available slot with no session → gate → proceed to book (`book_slot` unchanged).
   - My bookings: tab with no session → gate → list my bookings.
   - Video purchase: buy → gate → paymob checkout.
   - `AuthGateway` interface unchanged.
3. **Persist silently**: `supabase_flutter` handles persistence already; verify router no longer bounces → session restored on next open.
4. Tests (`flutter test`): router no-redirect tests; gate shows phone step when logged out, skips when logged in; booking proceeds after verify (fake gateway); existing widget tests updated (they asserted forced redirect — update to new behavior).

## 6. Admin web work (Task D)

1. `admin_auth_provider.dart`: after `verifyOtp` + role check → call `verify_admin_pin(pin)`; new state `pinRequired` (OTP passed, pin needed) / `pinLocked`. Login screen: phone → OTP → **PIN entry step** (4–6 digits). Every session; no session persistence on web (default).
2. Super-admin: set/reset PIN via RPCs (surface: users list → set pin dialog; reserve for Task D+ if scope grows — but tests included).
3. Tests: widget tests for 3-step login; provider tests for pin states (fake client).
4. Strings: PIN labels in Arabic (`كلمة مرور الإدارة`, `الرمز الحارس` etc.) — keep consistent with `AppStrings` pattern.

## 7. Rollout & risks

- **Meta approval of `otp_auth` template** — required before live OTP works; template exists in dispatcher map already (1 param). Already in external checklist.
- **Supabase project setting change** (human step, needs dashboard): Auth → SMS → Custom provider → webhook URL. Wizard doc later if needed.
- Numbers without WhatsApp → cannot receive OTP; note in app: "سيصلك الرمز عبر واتساب". (SMS fallback deferred — D1.)
- CGI: `event-dispatcher` already knows `otp_auth` (paramCount 1) — no change there.

## 8. Task order & TDD

A (otp-sms fn) → B (0034 + tests) → C (mobile) → D (admin). Each task: failing test first → implement → PASS → **commit per task**. Reviewer: OpenCode/agy relay per existing workflow, 100% approval gate before next task.

## 9. Plan-writing checklist compliance

- Enum sync: no new enums. `app_role` untouched (0033 collapse already done).
- RLS: `admin_pins` gets `enable row level security` statement; policies none; RPCs SECURITY DEFINER (matches `event_outbox` precedent).
- Fixtures: every test file has explicit INSERTs (0034 test, otp-sms deno tests, flutter tests) ⚠️ verified per task.
- Column names from migrations actual `CREATE TABLE` above.
- Empty-DB: `admin_pin_status` handles no-pin day-1. `verify_admin_pin` no-pin → false not crash.
- Index names: unique — `uq_admin_pins_attempts` etc. grep before use ⚠️.
- No stubs: `verify_admin_pin` full impl + failure tests.
- Master plan §6 diagram / §5: add `admin_pins` to master plan §5 schema list ⚠️ same commit as Task B.