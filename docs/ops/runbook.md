# Operations Runbook â€” Church Digital Platform

This runbook documents operational procedures, deployment steps, background jobs, backup policies, and monitoring for the Coptic Church Digital Platform.

---

## 1. Backup Schedule & Verification

### Schedule & Strategy
* **Automated Daily Backups:** Managed by Supabase infrastructure (nightly retention window).
* **Point-In-Time Recovery (PITR):** Enabled on Supabase Pro plan (up to 7-day or 14-day log retention).
* **Manual / Offline Dumps:** Standard PostgreSQL `pg_dump` can be scheduled via external runner or executed before major schema migrations.

### How to Verify Backups
1. Log into the [Supabase Dashboard](https://supabase.com/dashboard).
2. Navigate to **Project Settings** -> **Database** -> **Backups**.
3. Confirm daily snapshot timestamps and PITR status.
4. Periodically perform a restore drill (see [`restore-drill.md`](file:///c:/church/docs/ops/restore-drill.md)).

---

## 2. WhatsApp Template Change Process

When modifying or adding WhatsApp notifications sent via `whatsapp_outbox`:

1. **Meta Submission:** Submit new/updated template in Meta WhatsApp Business Manager.
2. **Approval Verification:** Wait for status to change to `APPROVED`.
3. **Test Run:** Trigger test notification to designated developer/admin mobile number.
4. **Code Update:** Update edge function or DB outbox generator with approved template name and parameters.

---

## 3. Edge Function Deployments & Secrets Management

### Deployment
To deploy an edge function (e.g., `analytics-export`):

```bash
npx supabase functions deploy analytics-export --project-ref <PROJECT_REF>
```

### Managing Environment Secrets
Secrets are kept in Supabase Vault / Edge Function Secrets:

```bash
# View active secrets
npx supabase secrets list --project-ref <PROJECT_REF>

# Set new secret
npx supabase secrets set KEY=VALUE --project-ref <PROJECT_REF>
```

Secrets configured per edge function:
* `SUPABASE_URL`
* `SUPABASE_ANON_KEY`
* `SUPABASE_SERVICE_ROLE_KEY`
* `PAYMOB_API_KEY` / `PAYMOB_HMAC_SECRET`

---

## 4. Scheduled Jobs (`pg_cron`)

Background jobs run inside PostgreSQL via `pg_cron`:

```sql
-- View all active cron jobs
SELECT * FROM cron.job;

-- View recent job execution history
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 20;
```

### Active Jobs
* `analytics-nightly`: Runs nightly at 02:00 UTC (`0 2 * * *`) executing `SELECT public.materialize_analytics();`.
* `whatsapp-outbox-drain`: Runs every minute (`* * * * *`) to process unsent notifications.

---

## 5. Production Supabase Vault Provisioning

Three internal secrets MUST be provisioned directly in Supabase Vault on production / staging environments:

1. `COMPLAINTS_KEY`: Symmetric AES encryption passphrase used by `public.submit_complaint_secure` and `public.decrypt_complaint`.
2. `SUPABASE_URL`: Internal API URL (e.g. `http://kong:8000` locally, or production Supabase project API gateway) for `pg_net` background dispatch triggers.
3. `SERVICE_ROLE_KEY`: Supabase `service_role` JWT secret for internal edge function RPC invocation.

### Provisioning Procedure
```sql
-- Run as superuser in Supabase SQL editor (never commit production secrets to repository):
SELECT vault.create_secret('<PROD_COMPLAINTS_KEY>', 'COMPLAINTS_KEY');
SELECT vault.create_secret('<PROD_SUPABASE_GATEWAY_URL>', 'SUPABASE_URL');
SELECT vault.create_secret('<PROD_SERVICE_ROLE_KEY>', 'SERVICE_ROLE_KEY');

-- Verify preflight check returns 0 missing rows:
SELECT * FROM public.vault_preflight();
```

> [!IMPORTANT]
> Real production secret values are **never committed** to git. `supabase/seed.sql` contains mock keys for local development only.

---

## 6. User Lifecycle & Deletion Policy

* **Hard User Deletion is Unsupported**: Direct `DELETE FROM public.users` or `DELETE FROM auth.users` will be rejected by foreign key restrictions (`ON DELETE RESTRICT`) whenever the user has associated records (e.g., `bookings`, `complaints`, `waiting_list`).
* **Soft Deletion (`users.deleted_at`)**: To deactivate a user, set `UPDATE public.users SET deleted_at = now() WHERE id = <USER_ID>;`.
* **Data Erasure / Privacy Compliance**: Full anonymizing erasure RPC is deferred for future implementation in compliance with Egypt's Personal Data Protection Law (PDPL Law 151/2018).

---

## 7. Monitoring & Incident Handling

* **Database Metrics:** Monitor active connections, CPU/Memory usage, and query performance in Supabase Dashboard -> Reports.
* **Edge Function Logs:** Check `npx supabase functions logs <function-name>` or Sentry dashboard.
* **Failure Alerts:** Webhook failures enqueue `refund_requests` or record error states in audit log.

## Browser Test Portals — Privileged Workflow Policy (010)

Portals under `test-apps/` run on the anon key only (zero credential literals).
Every workflow must complete while signed in as a **seeded role account**
(switcher cards: USER / ADMIN / SUPER_ADMIN).

**Decision rule**: if a workflow still returns FORBIDDEN under the highest seeded
role, it drops out of browser coverage into this manual checklist:

1. `supabase secrets set` / vault provisioning checks — use SQL editor as postgres.
2. Any direct DML on `payments`, `users`, `roles_permissions`, `audit_log` — use
   service-role SQL session (psql via docker exec), never the browser.
3. Storage bucket policy changes — apply via forward migration.

Record any newly discovered FORBIDDEN-under-seeded-roles screen here with date +
owner so it does not silently regress to a privileged browser client.
