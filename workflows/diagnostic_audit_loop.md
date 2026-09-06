# Workflow: Autonomous Backend Diagnostic & Security Audit Loop

## Loop Lens
- **Recurring Cycle:** Continuous automated audit running every hour / nightly via Supabase `pg_cron`.
- **Primary Operator:** Admin (alert phone configured via the `DIAGNOSTIC_ALERT_PHONE` env secret on the function).

---

## 1. Trigger
- **Engine Type:** Self-hosted Deno Edge Function (`diagnostic-engine`) deployed to Supabase.
- **Schedule Trigger:** `pg_cron` job running every 6 hours via `net.http_post` or internal trigger:
  ```sql
  select cron.schedule(
    'supabase-diagnostic-audit-loop',
    '0 */6 * * *',
    $$
    select net.http_post(
      url := 'https://qksgphryemrdrkwaqnxp.supabase.co/functions/v1/diagnostic-engine',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'SUPABASE_SERVICE_ROLE_KEY')
      ),
      body := '{}'::jsonb
    );
    $$
  );
  ```

---

## 2. Autonomous Execution (Push Right)
The self-hosted engine autonomously runs through four agent stages with zero human intervention:
1. **Explorer Agent:** Introspects `information_schema.tables`, `pg_policies`, `pg_proc`, PostgREST views, and active Edge Function routes.
2. **Brain Agent:** Deduces expected role matrices (`anon`, `parishioner`, `admin`, `service_role`), builds adversarial attack payloads (direct write attempts, forged Paymob webhook HMACs, unverified state transitions).
3. **Execution Agent:** Performs real network HTTP/RPC requests using actual JWTs and keys against the live database instance.
4. **Auditor Agent:** Verifies RLS leak absence, state transition integrity, and outbox event enqueueing.

---

## 3. Checkpoint & Alert Brief (Decision Gate)
- **Execution Policy:** Runs fully autonomously when status is `100% SECURE & INVARIANT-COMPLIANT`.
- **Checkpoint Trigger:** Activates **ONLY** when a `CRITICAL` RLS leak or `MAJOR` functional regression is detected.
- **Decision Brief Dispatch:**
  1. **WhatsApp Alert (Admin Phone via `DIAGNOSTIC_ALERT_PHONE`):**
     - Enqueues high-priority alert to `event_outbox` (`handler_type = 'WHATSAPP'`).
     - Content: Brief summary of failure target, severity, and instant incident identifier.
  2. **GitHub Issue Dispatch:**
     - Creates blocking GitHub issue with reproduction payload JSON and exact SQL remediation script.

---

## 4. Remediation Protocol
- **Human Authority:** Human engineer verifies the Brief and decides whether to apply the provided forward migration patch (`supabase/migrations/00XX_hotfix.sql`).
- **No Unreviewed Auto-DDL:** Engine provides the exact copy-paste SQL fix, preventing destructive schema alterations without explicit authorization.
