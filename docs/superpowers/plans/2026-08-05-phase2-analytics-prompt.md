# Agent Prompt — Complete Phase 2 Analytics Implementation (gaps only)

> Paste this prompt into a fresh implementation agent session (subagent-driven-development / executing-plans style).

---

## Context

Repo: `C:\church` — Church Digital Platform (Supabase backend + Flutter mobile + Flutter Web admin). CMeeting module was removed from scope; current scope = booking/payment engine + paid videos + analytics (4 roles: PARISHIONER/PRIEST/ADMIN/SUPER_ADMIN, 15 tables).

**Read first (mandatory, in order):**
1. `docs/superpowers/plans/2026-08-05-church-digital-platform.md` §1 (decisions A1–A11), §5, §8 Phase 2, §15 DoD
2. `docs/superpowers/plans/conventions.md`
3. `docs/superpowers/plans/2026-08-05-phase2-analytics.md` — the task plan (6 tasks, 0022–0027). Implement ONLY the gaps listed below; do not redo completed work.

## Current implementation state (verified)

| File | Status |
|---|---|
| `supabase/migrations/0022_analytics_aggregates.sql` | EXISTS (slot_utilization_monthly, payments_monthly, bookings_monthly, materialize_analytics(), cron) — keep, verify against plan |
| `supabase/migrations/0023_analytics_views.sql` | EXISTS (v_analytics_utilization/payments/bookings, security_invoker, RLS policies) — keep, verify against plan |
| `supabase/functions/analytics-export/index.ts` | EXISTS (buildCsv, exportAllowed, reports utilization\|payments\|bookings) — keep, verify against plan |
| `supabase/functions/analytics-export/index_test.ts` | EXISTS (buildCsv BOM/guard + role checks) — keep |
| `apps/admin/lib/features/analytics/utilization_screen.dart` | EXISTS |
| `apps/admin/lib/features/analytics/payments_screen.dart` | EXISTS |
| `apps/admin/lib/features/analytics/bookings_screen.dart` | EXISTS |
| `apps/admin/test/analytics_screens_test.dart` | EXISTS (3 smoke tests) |
| `apps/admin/pubspec.yaml` | fl_chart ^0.70.0 already present — do NOT add |

**Gaps — the actual work:**

1. **SQL tests missing** (plan Tasks 1–2):
   - Create `supabase/tests/0022_analytics_aggregates_test.sql`
   - Create `supabase/tests/0023_analytics_views_test.sql`
   Copy the failing-test SQL verbatim from the plan (fixtures included), adapt only if the existing migration differs from the plan SQL (then fix the migration to match the plan, not the test).
2. **Ops docs missing** (plan Task 5):
   - Create `docs/ops/runbook.md` (backup schedule + verify, WhatsApp template change process, edge function deploy + secrets, pg_cron listing, monitoring)
   - Create `docs/ops/restore-drill.md` (PITR via dashboard + local pg_dump/pg_restore path; drill checklist; execute against local stack if available, else record "pending staging")
3. **DoD doc missing** (plan Task 6):
   - Create `docs/release/` and `docs/release/project-dod.md` (master §15 items; mark items verified vs pending; note environment constraints)
4. **Verify existing impl matches plan** (all files in the table above, plus new tests) — if the implemented SQL/view/edge-fn/screen drifts from the plan, fix the code to match the plan.

## Discipline

- Test-first: write each test, run → FAIL, implement/verify → PASS, commit. Do NOT skip test steps.
- Do not rename/re-number existing migrations (0022/0023 stay; plan numbering is final).
- No CMeeting artifacts: never introduce members/households/attendance/visits/alerts tables, SERVANT role, alert_type/attendance_method/member_status enums, Drift/offline.
- Keep Arabic strings + EGP prices as-is.
- Commit per task with the plan's message convention:
  - `feat(analytics): aggregation tables + nightly materialization` (already committed — only commit new test files: `test(analytics): 0022 aggregates tests` / `test(analytics): 0023 views RLS tests`)
  - `feat(analytics): CSV export edge function with role check` (done — skip)
  - `feat(analytics): dashboard screens with fl_chart + CSV export` (done — skip)
  - `docs(ops): runbook + restore drill executed`
  - `docs(project): final DoD verification and handover`

## Verification commands (environment constraints)

- SQL: `npx supabase db reset` + `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/XXXX_name.sql` — expected no output, exit 0. ⚠️ **Docker is NOT installed on this machine** — `supabase start` will fail. If you cannot bring up a local stack, do rigorous static verification (parse-check SQL, cross-check column names against `0001_init_schema.sql` CREATE TABLEs) and mark tests as "written, not yet executed" in the DoD doc.
- Edge fn: `deno test --allow-env supabase/functions/analytics-export/` — ⚠️ **deno NOT installed**. Static verify only.
- Flutter: `flutter test apps/admin/test/analytics_screens_test.dart` — ✅ **flutter 3.44.0 IS available, run this**.
- If you have credentials for the linked remote project (`qksgphryemrdrkwaqnxp`, `apps/*/.env` has URL+anon key but NO DB password), you may run read-only verification queries; do NOT push migrations or run `db push` without explicit approval.

## Definition of done

- [ ] `supabase/tests/0022_analytics_aggregates_test.sql` + `0023_analytics_views_test.sql` created, committed, static-verified
- [ ] Existing 0022/0023/analytics-export/screens reconciled with plan (no drift)
- [ ] `docs/ops/runbook.md`, `docs/ops/restore-drill.md` created, committed
- [ ] `docs/release/project-dod.md` created with honest verification status, committed
- [ ] `flutter test apps/admin/test/` passes
- [ ] Report: list of files created/modified, test results (or "not run" + why), and any plan-vs-code drift found and fixed
