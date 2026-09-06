# Database Restore Drill & Disaster Recovery Procedure

This document specifies the disaster recovery drill procedure and records test results for database restore verification.

---

## Disaster Recovery Paths

### Path A: Point-In-Time Recovery (PITR) via Supabase Dashboard
1. Open [Supabase Dashboard](https://supabase.com/dashboard) -> **Project Settings** -> **Database** -> **Backups**.
2. Click **Restore** on the target point-in-time snapshot.
3. Specify target project / instance name.
4. Verify schema, RLS policies, and data integrity after restoration finishes.

### Path B: Manual Backup & Cross-Region Restore (`pg_dump` / `pg_restore`)
Used for offsite backups, cross-region migration, or local development setup.

```bash
# 1. Take compressed dump of source database
pg_dump "postgresql://postgres:<PASSWORD>@db.<PROJECT_REF>.supabase.co:5432/postgres" \
  --format=custom --file=church_prod_backup.dump

# 2. Restore into target database instance
pg_restore --clean --if-exists --no-owner --no-privileges \
  --dbname="postgresql://postgres:<PASSWORD>@<TARGET_HOST>:5432/postgres" \
  church_prod_backup.dump
```

---

## Disaster Recovery Drill Checklist

- [ ] Execute `pg_dump` snapshot or trigger PITR restore into scratch project.
- [ ] Connect `psql` to restored instance.
- [ ] Verify core table row counts (`auth.users`, `services`, `service_slots`, `bookings`, `payments`).
- [ ] Run test suite against restored database (`supabase/tests/*_test.sql`).
- [ ] Confirm RLS policies remain enabled (`SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public';`).
- [ ] Confirm `pg_cron` extension and scheduled jobs are intact.

---

## Execution Log & Drill Results

| Execution Date | Environment | DR Path | Status | Verification Result | Verified By |
|---|---|---|---|---|---|
| 2026-08-09 | Local CLI | Local pg_dump | Pending Staging | Local Docker stack unavailable; static SQL verification passed | AI Assistant |

> Note: Full execution of restore drill is scheduled on staging environment upon initial deployment.
