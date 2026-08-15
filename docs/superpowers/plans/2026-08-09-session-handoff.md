# Session Handoff — Backend Architecture Fixes DONE, Mobile Plan Next

**Date:** 2026-08-09. Written so a fresh chat can pick up with zero prior context.
**Rule for the new session:** read `AGENTS.md` fully, then this file, then start the mobile plan.

---

## 1. What this repo is

Planning workspace (docs + supabase migrations/tests/edge functions; **Flutter apps NOT yet built** — `apps/mobile` and `apps/admin` are empty scaffolds with only `.env` files). Egyptian Coptic church platform: Flutter mobile (parishioners) + Flutter Web admin, backend = Supabase (Postgres 16 + RLS + PostgREST + Deno Edge Functions + pg_cron). No live streaming (recorded → YouTube unlisted, sold via Paymob + WhatsApp).

## 2. Source-of-truth files (read before ANY edit)

- `docs/superpowers/plans/2026-08-05-church-digital-platform.md` — master blueprint, locked decisions A1–A11, §6 state machine, §5 schema list
- `docs/superpowers/plans/conventions.md` — authoritative conventions (slot locking, RLS/RPC rules, edge-function pattern, outbox pattern, enums)
- `docs/superpowers/plans/2026-08-09-backend-architecture-fixes.md` — **COMPLETE (all 5 tasks landed)** — still has a "Verification checklist (before handoff)" section (lines 859–868) that is OWED
- `docs/superpowers/plans/2026-08-09-mobile-architecture-fixes.md` — **NEXT PLAN**, 6 tasks, not started
- `docs/external-onboarding-checklist.md` — external deps critical path (Paymob/Meta/YouTube/Play)

## 3. Commit history (this session, in order)

| Commit | Message | What |
|---|---|---|
| `3456d71` | feat(supabase): transition engine 0024 | Backend Task 1 (pre-session) |
| `0c0a30c` | (backend) fix: centralize RBAC role checks | Task 2: 0025 `is_admin()`/`is_admin_or_priest()`/`is_super_admin()` replace repeated `current_user_role() in (...)` across 0002/0004/0005/0006/0008/0011/0019/0023 |
| `ed2e7bc` | (backend) fix: complaints crypto in-DB | Task 3: 0026 `submit_complaint_secure`/`decrypt_complaint` via pgp_sym_encrypt + Vault `COMPLAINTS_KEY`; deleted `complaints-encrypt`/`complaints-decrypt` edge functions |
| `7bbcd8a` | chore: remove stray skills copy | Purged `.agents/skills/` (152 files) that a prior session committed in `09d8f88` |
| `46ad2b9` | (docs) fix: complaints crypto refs; add .gitignore | phase1-mvp Tasks 2/3 rewritten to in-DB design; master A11 moved COMPLAINTS_KEY to Vault; new `.gitignore` (`.agents/`, `.claude/`, `.windsurf/`, `node_modules/`) |
| `b407782` | (backend) fix: unified event_outbox + event-dispatcher | Task 4: 0027 `event_outbox` + `event-dispatcher` edge fn + one cron replace `whatsapp_outbox`+`refund_requests` dual drains; enums `event_handler_type`/`outbox_status` back-propagated to 0001 + conventions; deleted `whatsapp-sender`, `paymob-refund`, 0018; rewired 0012/0014/0016/0017/0019; all 7 affected SQL tests + e2e updated |
| `019a9a9` | (backend) fix: shared client factory + analytics-export deps | Task 5: `_shared/client.ts` (`makeServiceClient`/`makeAnonClient`); `analytics-export` refactored to injected `Deps` + 401/403/405/400/month-filter tests; serve closures of paymob-checkout/webhook, reconcile-payments, youtube-expiry, event-dispatcher use factories |

## 4. Gate status — what is verified vs OWED

VERIFIED (this machine): `deno test --no-check --allow-env --allow-net supabase/functions/` → **27 passed, 1 failed**.

**OWED (needs Docker — not available locally):** the backend plan's handoff checklist (lines 859–868):
1. `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/run_all.sql` → no output, exit 0 (27 test files, 0001–0027)
2. `npx supabase db reset` → migrations 0001–0027 apply clean; cron jobs: `expire-bookings`, `event-dispatcher`, `reconcile-payments`, `youtube-expiry`, `analytics-nightly`
3. e2e `node supabase/e2e/book_pay_flow.mjs` → PASS
4. Greps zero (outside history): `whatsapp_outbox|refund_requests|whatsapp-sender|paymob-refund|trg_bookings_audit|complaints-encrypt|complaints-decrypt`

Run these on ANY Docker host (e.g., a machine with Docker Desktop + `npx supabase start`), or install Docker.

## 5. Known open issues (not this plan's scope — flag, don't silently fix)

- **`youtube-expiry/index_test.ts` FAILS pre-existing** (present since before backend plan): `JSON.parse(calls[0].body)` on a form-urlencoded OAuth body → `SyntaxError: Unexpected token 'g', "grant_type"...`. The test mocks the OAuth token response as JSON but the function sends form-urlencoded. Needs a small test fix (parse URLSearchParams) — or a real bug if the function genuinely returns JSON (it shouldn't). Worth its own small task.
- Migration `0002_rls_baseline.sql` still contains RLS policies for `whatsapp_outbox` (lines 32, 55) — dead code since 0027 drops the table (policies die with it). Harmless; optionally clean up in a future migration pass.
- `CONTEXT.md` at repo root is a stale domain glossary with mojibake Arabic — not a handoff doc; ignore it.
- `apps/mobile`/`apps/admin` have only `.env` — Flutter code doesn't exist yet.

## 6. How task execution runs (proven loop this session — reuse it)

1. Write a **brief** (XML blocks: `<task>`, `<verification_loop>`, `<action_safety>`, `<structured_output_contract>`) — paste the plan's exact SQL/TS blocks; tell agy to copy them character-for-character; name real gate commands; forbid git add/commit.
2. Dispatch: `node "C:\Users\KimoStore\.agents\skills\agy-delegate\scripts\relay.mjs" --brief <path> --cd "C:\church" --model gemini-3.6-flash-high`
3. **Do NOT trust the self-report** — re-run deno gates yourself, diff every file vs plan, grep leftovers.
4. Commit yourself with the plan's exact commit message; include gate status in the message body.
5. `gemini-3.6-flash-high` was chosen over `gemini-3.6-flash-medium` (user asked "see which is better") — 3/3 clean runs, caught one real plan bug (dedupe guard on `booking_id` needed `params` path). Keep high for the mobile plan.
6. **Gotcha:** every agy dispatch recreates `.agents/skills/` (Antigravity scaffolding) in the repo and removes it at end — churn only; `.gitignore` now blocks it. Don't commit it.

## 7. Mobile plan — next up (`2026-08-09-mobile-architecture-fixes.md`)

6 tasks, none started:
1. **Layered skeleton + repository interface**
2. **Booking status consolidation + BookSlotResult**
3. **Error mapping**
4. **GoRouter + safe navigation**
5. **DI wiring + Provider removal**
6. **Offline test suite**

First step of the new session: read the mobile plan's Task List + Task 1 sections, read `AGENTS.md` + `conventions.md` §Flutter Conventions + master plan §1 decisions, then brief/dispatch Task 1 the same way as above. Flutter gates: `flutter test apps/mobile/test/...` — verify a Flutter SDK exists on the host before promising that gate.

## 8. Enums currently in the system (checklist item 1 — sync BOTH conventions.md §Enums AND 0001)

`user_role` (PARISHIONER/PRIEST/ADMIN/SUPER_ADMIN), `booking_status`, `payment_status`, `complaint_status`, `waiting_list_status`, `event_handler_type` (WHATSAPP/PAYMOB_REFUND/FCM_PUSH/SMS), `outbox_status` (PENDING/PROCESSING/SENT/FAILED). Any new enum value must be added to BOTH files in the same edit.
