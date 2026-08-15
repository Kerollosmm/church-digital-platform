# Operations Runbook — Church Digital Platform

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
* `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` / `GOOGLE_REFRESH_TOKEN` (YouTube OAuth2)

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

## 5. Monitoring & Incident Handling

* **Database Metrics:** Monitor active connections, CPU/Memory usage, and query performance in Supabase Dashboard -> Reports.
* **Edge Function Logs:** Check `npx supabase functions logs <function-name>` or Sentry dashboard.
* **Failure Alerts:** Webhook failures enqueue `refund_requests` or record error states in audit log.
