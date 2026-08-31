# Church Digital Platform — Backend Audit & Architecture Report

**Date:** 2026-08-31
**Branch:** `feat/youtube-automation-backend-fixes`
**Reviewer:** Perplexity Computer
**Repo:** [github.com/Kerollosmm/church-digital-platform](https://github.com/Kerollosmm/church-digital-platform)
**Supabase project:** `church-app` ([qksgphryemrdrkwaqnxp](https://supabase.com/dashboard/project/qksgphryemrdrkwaqnxp))

---

## 1. Executive Summary

I audited the full backend (Supabase migrations, Edge Functions, CI, conventions) and implemented the first concrete fixes plus the missing **YouTube automation** integration.

**Headlines**

- The backend is in substantially better shape than the repo description suggests. 72 ordered migrations, a real RLS + `SECURITY DEFINER` RPC architecture, a transactional outbox for WhatsApp/FCM, a zero-leak Arabic error contract, and 58/58 Edge Function tests passing before my work.
- Found and fixed one genuine **CI bug**: the `deno check` step failed because `npm:` specifiers (`npm:jose@5`, `npm:@supabase/supabase-js@2`) couldn't resolve without a `node_modules` dir. Added `"nodeModulesDir": "auto"` to `supabase/functions/deno.json`.
- Built the **free-content YouTube catalog automation** (ADR 0004) — the explicit feature you asked for. This replaces the decommissioned paid-video machinery (ADR 0002) with read-only sermons/masses synced from the church's public channel.
- After my changes: **66/66 Edge Function tests pass**, `deno check` clean for all functions, all SQL test files present and registered in `run_all.sql`.

**Two commits on the feature branch:**

1. `fix(functions): set nodeModulesDir so deno check resolves npm deps`
2. `feat(youtube): free-content YouTube media catalog automation`

---

## 2. What's Already Good (keep as-is)

These are the load-bearing strengths of the current backend — I deliberately did **not** rewrite them:

- **RPC-first state machine.** Every booking/payment/slot transition goes through `SECURITY DEFINER` RPCs (`book_slot`, `apply_payment`, `transition_booking_status`, `submit_payment_proof`, `approve_payment_proof`, `mark_cash_received`, …). Apps never do raw table writes on money/bookings. This is the single most important architectural decision in the repo and it's correct.
- **Row Level Security everywhere**, with `tenant_id` default + invariant on every business table, `is_admin()`/`current_user_role()` helpers, explicit `REVOKE ALL ... FROM PUBLIC, anon, authenticated` on privileged RPCs, and pgtap penetration tests asserting denial for unprivileged roles.
- **Transactional outbox** (`event_outbox`) drained atomically by `event-dispatcher` via `claim_event_outbox_batch` (`FOR UPDATE SKIP LOCKED`), with WhatsApp + FCM handlers, exponential backoff, and max-attempts. No silent message loss.
- **Zero-leak Arabic error contract** (`_shared/http.ts`): 5xx bodies carry only a frozen error code + catalog Arabic sentence; provider detail stays in server logs. `otp-sms` and the dispatcher both honor it.
- **Manual payment rail (ADR 0003).** Paymob was decommissioned (`0070`); member-submitted proof → admin review queue → `approve/reject` RPCs → `apply_payment`. Clean and operationally honest for a single church.
- **WhatsApp integration** (Meta Graph API v20.0) with template allow-listing, `whatsapp_optins` opt-in gate, and `otp-sms` StandardWebhooks verification — all wired and tested.
- **CI pipeline** (`.github/workflows/ci.yml`) runs Flutter analyze/test (mobile + admin), SQL regression suite via local Supabase stack, and `deno test` — a solid 4-job gate with staging deploy on `main`.

---

## 3. Issues Found & Fixed This Session

### 3.1 CI bug — `deno check` failed (FIXED)

**Problem:** The `deno-tests` job runs `deno check $(find ... -name '*.ts' -not -name '*_test.ts')`. Under Deno 2, `npm:` specifiers (used by `event-dispatcher` for `npm:jose@5`) require a `node_modules` directory; `supabase/functions/deno.json` didn't set `nodeModulesDir`, so type-checking failed with `Could not find a matching package for 'npm:jose@5'`. The CI job would therefore fail on every push/PR once the cache was cold.

**Fix:** Added `"nodeModulesDir": "auto"` to `supabase/functions/deno.json` and refreshed `deno.lock`. Verified `deno check` now passes for all 5 shared modules + 4 functions (incl. the new `youtube-sync`).

### 3.2 Dead code — unused `amountMultiplier` (FIXED)

**Problem:** `event-dispatcher/index.ts` `Deps` interface declared `amountMultiplier?: number` that no handler or caller ever read.

**Fix:** Removed the field.

### 3.3 Missing YouTube automation (FIXED — ADR 0004)

**Problem:** You explicitly asked for "youtube automation inside the project." The old paid-video machinery (`videos`, `video_purchases`, `purchase_video`, `apply_video_payment`, `youtube-expiry` cron) was **decommissioned** by ADR 0002 and fully dropped in migration `0053`. The `video_privacy` enum was dropped in `0062`. So the repo had **zero** YouTube automation — but the church clearly broadcasts masses/sermons publicly and the product context (`CONTEXT.md`) lists "Church Services & Masses" and "About Us & Church" as core pillars.

**Fix — free-content YouTube catalog (ADR 0004):** A complete, conventions-compliant feature:

- **Migration `0073_youtube_media_catalog.sql`** — `youtube_videos` table (one row per synced video per tenant), unique index on `(tenant_id, yt_video_id)`, RLS (anon + authenticated public read of available rows; admin write), `tenant_id` default + invariant, granular DML grants, identity sequence grant, `updated_at` trigger. `sync_youtube_videos(p_channel_id, p_videos)` `SECURITY DEFINER` RPC as the **single sanctioned write seam**: upserts the batch and marks videos absent from the batch `is_available = false` (removed/made-private on YouTube) while preserving row identity. Revoked from `PUBLIC/anon/authenticated`, service-role only. Public read view `v_sermons` (explicit columns). `pg_cron` hourly schedule posting to the edge function via Vault-stored service-role key.
- **`youtube-sync` Edge Function** — YouTube Data API v3: paginates the channel uploads playlist (`UC… → UU…`, up to 3 pages × 50), fetches durations in a single `videos.list` batch (1 quota unit), calls `sync_youtube_videos`. Cron/service-role auth via `verifyCronOrServiceAuth`. Zero-leak errors (`UPSTREAM_ERROR`/`INTERNAL`); duration-fetch failure is non-fatal. Quota bounded at ≤150 videos + 1 `videos.list` per run.
- **Tests** — 8 Deno tests (auth, missing key, happy path, 4xx/5xx upstream, RPC error, empty catalog, duration parsing, playlist resolution) + a pgtap-style SQL test (`0073_youtube_media_catalog_test.sql`, registered in `run_all.sql`) covering RLS, upsert/mark-unavailable, anon/user denial, and RPC revocation.
- **Docs** — ADR 0004, conventions External Integrations entry, functions README catalog, `.env.example` secrets.

---

## 4. Remaining Work (recommendations, not yet done)

These are the highest-value next steps I'd suggest. I did **not** attempt them this session because each warrants its own task/PR and some need your input (credentials, product calls).

### 4.1 Apply migrations + secrets to the live `church-app` Supabase project

The new migration (`0073`) and the full set of existing migrations (`0001`–`0072`) need to be pushed to the `qksgphryemrdrkwaqnxp` project. This requires:
- A Supabase access token + `SUPABASE_PROJECT_REF` in GitHub secrets (CI `deploy-staging` job already expects these).
- `supabase link --project-ref qksgphryemrdrkwaqnxp` then `supabase db push`.
- Setting edge function secrets: `supabase secrets set YOUTUBE_API_KEY=... YOUTUBE_CHANNEL_ID=UCxxxx WHATSAPP_TOKEN=... WHATSAPP_PHONE_ID=... FCM_PROJECT_ID=... FCM_CLIENT_EMAIL=... FCM_PRIVATE_KEY=... CRON_SECRET=...`.
- Deploying functions: `supabase functions deploy youtube-sync event-dispatcher otp-sms diagnostic-engine analytics-export`.

I cannot run these from here without your Supabase access token and the external API keys. I can drive this end-to-end in a follow-up if you grant access.

### 4.2 Push the branch and open a PR

I created the commits locally on `feat/youtube-automation-backend-fixes`. Pushing to `origin` and opening a PR needs GitHub write access to `Kerollosmm/church-digital-platform` — the GitHub connector was returning 503 during this session. I can push and open the PR (titled "feat: YouTube automation + CI deno check fix") as soon as access is available.

### 4.3 Flutter apps don't yet consume the sermons catalog

The mobile/admin apps have no screen that reads `v_sermons`. Adding a "Sermons/Masses" list screen (cached YouTube thumbnails → open `yt_url`) in `apps/mobile` would surface the new automation to parishioners. This is a self-contained Flutter task following the existing Riverpod + GoRouter + repository-seam pattern.

### 4.4 Supabase project name mismatch

You said the Supabase project name is `church-app`, but the repo's `supabase/config.toml` uses `project_id = "church"` and the README/docs reference `church`. Not a bug (local `project_id` is just a local label), but worth aligning the dashboard name and docs to avoid confusion.

### 4.5 Schema hardening opportunities (minor, observed during audit)

- `payments.booking_id` was made nullable in `0019` for the now-deleted video feature; since video payments are gone, consider a follow-up migration adding `NOT NULL` back (with a backfill guard) to tighten the money boundary.
- A couple of older migrations use `GRANT ALL` on content tables (e.g. `social_links`) where granular `SELECT, INSERT, UPDATE, DELETE` would be more conservative — the conventions now say "never `GRANT ALL`". A cleanup migration could tighten these.

---

## 5. How to verify my work locally

```bash
git fetch && git checkout feat/youtube-automation-backend-fixes

# Edge functions type-check + tests (66/66)
cd supabase/functions
deno install
deno check $(find . -name '*.ts' -not -name '*_test.ts' -not -path './_tests/*' -not -path './node_modules/*')
deno test --allow-env --allow-net

# SQL regression suite (requires local Supabase stack)
cd ../..
npx supabase start
npx supabase db reset
DB=$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1)
docker cp supabase/tests "$DB":/tmp/church_tests
docker exec -i "$DB" psql -U postgres -d postgres -f /tmp/church_tests/run_all.sql
```

---

## 6. Files Changed

| File | Change |
| :--- | :--- |
| `supabase/functions/deno.json` | +`nodeModulesDir: auto` (CI fix) |
| `supabase/functions/deno.lock` | refreshed resolved deps |
| `supabase/functions/event-dispatcher/index.ts` | removed dead `amountMultiplier` |
| `supabase/migrations/0073_youtube_media_catalog.sql` | new — catalog + RPC + view + cron |
| `supabase/functions/youtube-sync/index.ts` | new — YouTube Data API sync |
| `supabase/functions/youtube-sync/index_test.ts` | new — 8 tests |
| `supabase/tests/0073_youtube_media_catalog_test.sql` | new — RLS + RPC test |
| `supabase/tests/run_all.sql` | registered 0073 test |
| `supabase/config.toml` | `[functions.youtube-sync]` entry |
| `supabase/functions/README.md` | catalog table updated |
| `docs/adr/0004-youtube-media-catalog.md` | new ADR |
| `docs/superpowers/plans/conventions.md` | YouTube integration entry |
| `.env.example` | YouTube secrets documented |

**+910 / −4 across 13 files.**
