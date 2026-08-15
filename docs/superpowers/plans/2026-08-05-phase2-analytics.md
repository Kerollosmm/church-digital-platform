# Phase 2 — Analytics & Insights Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the platform's operational data into pastoral decisions: slot utilization per service, payment reports (paid/refunded totals), and booking trends (volume + status mix) — viewable in the admin dashboard and exportable as CSV. Answers in <1 min: "which slots are underutilized", "how are payments/refunds trending", "how do bookings look this month".

**Architecture:** Nightly pg_cron materialization into dedicated analytics tables (idempotent delete-and-recompute per month), read-only views with PRIEST/ADMIN RLS, CSV export via an Edge Function, Flutter Web dashboard screens with fl_chart. No new source tables; source data (service_slots, bookings, payments) is untouched.

**Tech Stack:** Supabase (PostgreSQL 16, pg_cron, RLS, date_trunc), Deno edge function (CSV export with JWT role check), Flutter Web (fl_chart, client-side CSV build, share via url_launcher/share_plus), existing Phase 0-1 schema.

**Depends on:** master blueprint `docs/superpowers/plans/2026-08-05-church-digital-platform.md` (§8 Phase 2, M5, §15 DoD), Phase 1 `2026-08-05-phase1-mvp.md` (migrations 0004-0020).

**Migration numbering:** Phase 2 owns **0022-0030**. This plan uses SQL migrations 0022-0023 (analytics tables + views); tasks 0024-0027 are non-SQL (edge function, Flutter screens, ops docs, DoD). All psql commands use `postgresql://postgres:postgres@127.0.0.1:54322/postgres` after `supabase db reset`.

---

### Task 1: Analytics Aggregation Tables + Nightly Materialization (0022)

**Files:**
- Create: `supabase/migrations/0022_analytics_aggregates.sql`
- Test: `supabase/tests/0022_analytics_aggregates_test.sql`

- [ ] **Step 1: Write the failing test**

```sql
-- supabase/tests/0022_analytics_aggregates_test.sql
DO $$
DECLARE slots_total int; slots_booked int; bookings_total int; conf int;
        total_paid numeric; total_refunded numeric; count_paid int;
BEGIN
  -- fixtures: 1 service, 2 slots this month (capacity 50 each), 1 CONFIRMED + 1 PENDING_PAYMENT booking, 1 PAID + 1 REFUNDED payment
  INSERT INTO public.services (id, title_ar, tenant_id)
    VALUES (901, 'قداس اختبار', '00000000-0000-0000-0000-000000000001') ON CONFLICT DO NOTHING;
  INSERT INTO public.service_slots (id, service_id, starts_at, ends_at, capacity, price, tenant_id)
    VALUES (901, 901, date_trunc('month', now() AT TIME ZONE 'Africa/Cairo') + interval '1 day',
            date_trunc('month', now() AT TIME ZONE 'Africa/Cairo') + interval '1 day 2 hours', 50, 0, 1),
           (902, 901, date_trunc('month', now() AT TIME ZONE 'Africa/Cairo') + interval '8 days',
            date_trunc('month', now() AT TIME ZONE 'Africa/Cairo') + interval '8 days 2 hours', 50, 0, 1)
    ON CONFLICT DO NOTHING;
  INSERT INTO public.bookings (id, slot_id, user_id, status, tenant_id)
    VALUES (901, 901, (SELECT id FROM auth.users LIMIT 1), 'CONFIRMED', 1),
           (902, 902, (SELECT id FROM auth.users LIMIT 1), 'PENDING_PAYMENT', 1)
    ON CONFLICT DO NOTHING;
  INSERT INTO public.payments (id, booking_id, amount, status, tenant_id)
    VALUES (901, 901, 100, 'PAID', 1),
           (902, 902, 50, 'REFUNDED', 1)
    ON CONFLICT DO NOTHING;

  PERFORM public.materialize_analytics();

  SELECT slots_total, slots_booked INTO slots_total, slots_booked
    FROM public.slot_utilization_monthly
    WHERE month = (date_trunc('month', now() AT TIME ZONE 'Africa/Cairo'))::date LIMIT 1;
  IF slots_total != 2 OR slots_booked != 1 THEN
    RAISE EXCEPTION 'FAIL: utilization %, %', slots_total, slots_booked;
  END IF;

  SELECT bookings_total, (by_status->>'CONFIRMED')::int INTO bookings_total, conf
    FROM public.bookings_monthly
    WHERE month = (date_trunc('month', now() AT TIME ZONE 'Africa/Cairo'))::date LIMIT 1;
  IF bookings_total != 2 OR conf != 1 THEN
    RAISE EXCEPTION 'FAIL: bookings %, confirmed %', bookings_total, conf;
  END IF;

  SELECT total_paid, total_refunded, count_paid INTO total_paid, total_refunded, count_paid
    FROM public.payments_monthly
    WHERE month = (date_trunc('month', now() AT TIME ZONE 'Africa/Cairo'))::date LIMIT 1;
  IF total_paid != 100 OR total_refunded != 50 OR count_paid != 1 THEN
    RAISE EXCEPTION 'FAIL: payments %, %, %', total_paid, total_refunded, count_paid;
  END IF;

  -- idempotent: second run must not duplicate rows
  PERFORM public.materialize_analytics();
  IF (SELECT count(*) FROM public.slot_utilization_monthly
      WHERE month = (date_trunc('month', now() AT TIME ZONE 'Africa/Cairo'))::date) > 1 THEN
    RAISE EXCEPTION 'FAIL: duplicates';
  END IF;

  RAISE NOTICE 'PASS: materialize_analytics';
END $$;
```

- [ ] **Step 2: Run it, expect FAIL**

Run: `supabase db reset; psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0022_analytics_aggregates_test.sql`
Expected: FAIL — relation `slot_utilization_monthly` does not exist.

- [ ] **Step 3: Minimal implementation**

```sql
-- supabase/migrations/0022_analytics_aggregates.sql
CREATE TABLE IF NOT EXISTS public.slot_utilization_monthly (
  service_id bigint REFERENCES public.services(id) ON DELETE CASCADE,
  month date NOT NULL,
  slots_total int NOT NULL DEFAULT 0,
  slots_booked int NOT NULL DEFAULT 0,
  utilization_pct numeric(5,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (service_id, month)
);

CREATE TABLE IF NOT EXISTS public.payments_monthly (
  month date NOT NULL,
  total_paid numeric(12,2) NOT NULL DEFAULT 0,
  total_refunded numeric(12,2) NOT NULL DEFAULT 0,
  count_paid int NOT NULL DEFAULT 0,
  PRIMARY KEY (month)
);

CREATE TABLE IF NOT EXISTS public.bookings_monthly (
  service_id bigint REFERENCES public.services(id) ON DELETE CASCADE,
  month date NOT NULL,
  bookings_total int NOT NULL DEFAULT 0,
  by_status jsonb NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (service_id, month)
);

CREATE OR REPLACE FUNCTION public.materialize_analytics()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE m date := (date_trunc('month', now() AT TIME ZONE 'Africa/Cairo'))::date;
BEGIN
  DELETE FROM public.slot_utilization_monthly WHERE month = m;
  INSERT INTO public.slot_utilization_monthly (service_id, month, slots_total, slots_booked, utilization_pct)
  SELECT
    s.id, m,
    count(DISTINCT sl.id),
    count(DISTINCT b.slot_id),
    CASE WHEN count(DISTINCT sl.id) = 0 THEN 0
         ELSE round(100.0 * count(DISTINCT b.slot_id) / count(DISTINCT sl.id), 2) END
  FROM public.services s
  LEFT JOIN public.service_slots sl ON sl.service_id = s.id
    AND sl.starts_at AT TIME ZONE 'Africa/Cairo' >= m
    AND sl.starts_at AT TIME ZONE 'Africa/Cairo' < m + interval '1 month'
  LEFT JOIN public.bookings b ON b.slot_id = sl.id AND b.status IN ('AWAITING_CALL','CONFIRMED','COMPLETED')
  GROUP BY s.id;

  DELETE FROM public.payments_monthly WHERE month = m;
  INSERT INTO public.payments_monthly (month, total_paid, total_refunded, count_paid)
  SELECT m,
    COALESCE(sum(amount) FILTER (WHERE status = 'PAID'), 0),
    COALESCE(sum(amount) FILTER (WHERE status = 'REFUNDED'), 0),
    count(*) FILTER (WHERE status = 'PAID')
  FROM public.payments WHERE created_at AT TIME ZONE 'Africa/Cairo' >= m;

  DELETE FROM public.bookings_monthly WHERE month = m;
  WITH agg AS (
    SELECT sl.service_id, b.status, count(*) AS cnt
    FROM public.bookings b
    JOIN public.service_slots sl ON sl.id = b.slot_id
    WHERE b.created_at AT TIME ZONE 'Africa/Cairo' >= m
    GROUP BY sl.service_id, b.status
  )
  INSERT INTO public.bookings_monthly (service_id, month, bookings_total, by_status)
  SELECT a.service_id, m, sum(a.cnt), jsonb_object_agg(a.status::text, a.cnt)
  FROM agg a GROUP BY a.service_id;
END $$;

SELECT cron.schedule('analytics-nightly', '0 2 * * *', $$SELECT public.materialize_analytics()$$);
```

- [ ] **Step 4: Run it, expect PASS**

Run: `supabase db reset; psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0022_analytics_aggregates_test.sql`
Expected: `NOTICE: PASS: materialize_analytics` — no exceptions.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0022_analytics_aggregates.sql supabase/tests/0022_analytics_aggregates_test.sql
git commit -m "feat(analytics): aggregation tables + nightly materialization"
```

### Task 2: Read Views + RLS (0023)

**Files:**
- Create: `supabase/migrations/0023_analytics_views.sql`
- Test: `supabase/tests/0023_analytics_views_test.sql`

- [ ] **Step 1: Write the failing test**

```sql
DO $$
DECLARE n int;
BEGIN
  PERFORM public.materialize_analytics();
  SET ROLE anon;
  IF EXISTS (SELECT 1 FROM public.v_analytics_utilization) THEN
    RAISE EXCEPTION 'FAIL: anon sees analytics';
  END IF;
  RESET ROLE;
  SET ROLE authenticated;
  SELECT count(*) INTO n FROM public.v_analytics_utilization;
  IF n != 0 THEN RAISE EXCEPTION 'FAIL: non-admin sees analytics'; END IF;
  RESET ROLE;
  RAISE NOTICE 'PASS: analytics RLS';
END $$;
```

- [ ] **Step 2: Run it, expect FAIL**

Run: `supabase db reset; psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0023_analytics_views_test.sql`
Expected: FAIL — view `v_analytics_utilization` does not exist.

- [ ] **Step 3: Minimal implementation**

```sql
-- supabase/migrations/0023_analytics_views.sql
-- security_invoker: views run with the CALLER's rights, so RLS on the base tables applies
CREATE OR REPLACE VIEW public.v_analytics_utilization WITH (security_invoker = true) AS
SELECT s.title_ar, u.month, u.slots_total, u.slots_booked, u.utilization_pct
FROM public.slot_utilization_monthly u
JOIN public.services s ON s.id = u.service_id;

CREATE OR REPLACE VIEW public.v_analytics_payments WITH (security_invoker = true) AS
SELECT p.month, p.total_paid, p.total_refunded, p.count_paid
FROM public.payments_monthly p;

CREATE OR REPLACE VIEW public.v_analytics_bookings WITH (security_invoker = true) AS
SELECT s.title_ar, b.month, b.bookings_total, b.by_status
FROM public.bookings_monthly b
JOIN public.services s ON s.id = b.service_id;

ALTER TABLE public.slot_utilization_monthly ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments_monthly ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings_monthly ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_analytics_read_admin ON public.slot_utilization_monthly
  FOR SELECT USING (current_user_role() IN ('ADMIN','PRIEST','SUPER_ADMIN'));
CREATE POLICY p_analytics_read_admin ON public.payments_monthly
  FOR SELECT USING (current_user_role() IN ('ADMIN','PRIEST','SUPER_ADMIN'));
CREATE POLICY p_analytics_read_admin ON public.bookings_monthly
  FOR SELECT USING (current_user_role() IN ('ADMIN','PRIEST','SUPER_ADMIN'));
```

- [ ] **Step 4: Run it, expect PASS**

Run: `supabase db reset; psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0023_analytics_views_test.sql`
Expected: `NOTICE: PASS: analytics RLS`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0023_analytics_views.sql supabase/tests/0023_analytics_views_test.sql
git commit -m "feat(analytics): read views with PRIEST/ADMIN RLS"
```

### Task 3: CSV Export Edge Function (0024)

**Files:**
- Create: `supabase/functions/analytics-export/index.ts`
- Create: `supabase/functions/analytics-export/index_test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// supabase/functions/analytics-export/index_test.ts
import { assertEquals } from "jsr:@std/assert";
import { buildCsv } from "./index.ts";

Deno.test("builds CSV from rows with BOM + formula-char guard", () => {
  const csv = buildCsv(
    ["month", "rate_pct"],
    [["2026-08-01", "50.00"], ["2026-09-01", "66.67"], ["=1+1", "-0.50"]],
  );
  assertEquals(csv, "\uFEFFmonth,rate_pct\n2026-08-01,50.00\n2026-09-01,66.67\n'=1+1,'-0.50\n");
});

Deno.test("denies non-admin role", () => {
  assertEquals(exportAllowed("PARISHIONER"), false);
  assertEquals(exportAllowed("PRIEST"), true);
  assertEquals(exportAllowed("ADMIN"), true);
});
```

- [ ] **Step 2: Run it, expect FAIL**

Run: `deno test --allow-env supabase/functions/analytics-export/index_test.ts`
Expected: FAIL — no exports.

- [ ] **Step 3: Minimal implementation**

```ts
// supabase/functions/analytics-export/index.ts
import { createClient } from "npm:@supabase/supabase-js@2";

export function buildCsv(headers: string[], rows: string[][]): string {
  const esc = (v: string) => {
    const s = /^[=+\-@]/.test(v) ? "'" + v : v;
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return "\uFEFF" + [headers.map(esc).join(","), ...rows.map((r) => r.map(esc).join(","))].join("\n") + "\n";
}

export function exportAllowed(role: string | undefined): boolean {
  return role === "PRIEST" || role === "ADMIN" || role === "SUPER_ADMIN";
}

Deno.serve(async (req) => {
  if (req.method !== "GET") return new Response("method not allowed", { status: 405 });
  const url = new URL(req.url);
  const report = url.searchParams.get("report") ?? "";
  const month = url.searchParams.get("month") ?? "";
  if (!["utilization", "payments", "bookings"].includes(report)) {
    return new Response("unknown report", { status: 400 });
  }

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!);
  const authHeader = req.headers.get("Authorization") ?? "";
  const { data: { user } } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
  if (!user) return new Response("unauthorized", { status: 401 });
  const { data: profile } = await supabase.from("users").select("role").eq("id", user.id).single();
  if (!exportAllowed(profile?.role)) return new Response("forbidden", { status: 403 });

  const viewMap: Record<string, string> = {
    utilization: "v_analytics_utilization",
    payments: "v_analytics_payments",
    bookings: "v_analytics_bookings",
  };
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  let query = admin.from(viewMap[report]).select("*");
  if (month) query = query.eq("month", month);
  const { data, error } = await query;
  if (error) return new Response(error.message, { status: 500 });
  const rows = (data ?? []).map((r: Record<string, unknown>) => Object.values(r).map(String));
  const headers = data && data.length > 0 ? Object.keys(data[0]) : ["empty"];
  return new Response(buildCsv(headers, rows), {
    headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": `attachment; filename="${report}-${month}.csv"` },
  });
});
```

- [ ] **Step 4: Run it, expect PASS**

Run: `deno test --allow-env supabase/functions/analytics-export/index_test.ts`
Expected: PASS. Deploy: `supabase functions deploy analytics-export --project-ref $REF`.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/analytics-export/
git commit -m "feat(analytics): CSV export edge function with role check"
```

### Task 4: Admin Analytics Screens (fl_chart) (0025)

**Files:**
- Create: `apps/admin/lib/features/analytics/utilization_screen.dart`
- Create: `apps/admin/lib/features/analytics/payments_screen.dart`
- Create: `apps/admin/lib/features/analytics/bookings_screen.dart`
- Create: `apps/admin/test/analytics_screens_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
// apps/admin/test/analytics_screens_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:church_admin/features/analytics/utilization_screen.dart';

void main() {
  testWidgets('utilization screen renders title and empty state', (tester) async {
    await tester.pumpWidget(UtilizationScreen(supabase: fakeSupabase));
    expect(find.text('Slot utilization'), findsOneWidget);
    expect(find.text('No data yet'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it, expect FAIL**

Run: `flutter test apps/admin/test/analytics_screens_test.dart`
Expected: FAIL — screen not found.

- [ ] **Step 3: Minimal implementation**

Add dependency: `flutter pub add fl_chart` in `apps/admin`.

`utilization_screen.dart`: Riverpod `FutureProvider` fetching `v_analytics_utilization` (month asc), renders `BarChart` (utilization_pct per service/month); empty state text "No data yet"; service picker dropdown filters by `title_ar`.

`payments_screen.dart`: table from `v_analytics_payments` (month, total_paid, total_refunded, count_paid) + "Export CSV" button calling the edge function URL with `Authorization: Bearer <session>` then triggering download via `url_launcher` (or `share_plus` share sheet).

`bookings_screen.dart`: `LineChart` of bookings_total per month + status-mix breakdown from `by_status` jsonb (stacked legend) + export button.

- [ ] **Step 4: Run it, expect PASS**

Run: `flutter test apps/admin/test/analytics_screens_test.dart`
Expected: PASS (all smoke tests).

- [ ] **Step 5: Commit**

```bash
git add apps/admin/lib/features/analytics/ apps/admin/test/analytics_screens_test.dart apps/admin/pubspec.yaml
git commit -m "feat(analytics): dashboard screens with fl_chart + CSV export"
```

### Task 5: Ops Runbook + Restore Drill (0026)

**Files:**
- Create: `docs/ops/runbook.md`
- Create: `docs/ops/restore-drill.md`

- [ ] **Step 1: Write the runbook**

`docs/ops/runbook.md` covers: backup schedule (Supabase nightly + PITR on Pro), how to verify a backup (list backups in dashboard), WhatsApp template change process (submit in Meta → test with test number → update template registry in `whatsapp_outbox` docs), edge function deploy process (`supabase functions deploy` + secrets), pg_cron job listing (`select * from cron.job`), monitoring (Supabase dashboard metrics + Sentry for edge functions + Uptime Kuma optional).

- [ ] **Step 2: Write the restore drill**

`docs/ops/restore-drill.md`: two paths — (a) PITR via Supabase dashboard (Pro), (b) local `pg_dump`/`pg_restore` against `postgresql://...` for cross-region recovery. Drill checklist: take dump → restore into scratch project → run `supabase/tests/run_all.sql` → confirm counts match → document result.

- [ ] **Step 3: Execute the drill once (staging)**

Run the drill in staging with real data; record output in `docs/ops/restore-drill.md` result section.

- [ ] **Step 4: Commit**

```bash
git add docs/ops/
git commit -m "docs(ops): runbook + restore drill executed"
```

### Task 6: Final Project DoD Verification (0027)

**Files:**
- Create: `docs/release/project-dod.md`

- [ ] **Step 1: Write the project DoD checklist**

Map master plan §15: (1) parishioner book → pay → confirm → video link with real money, (2) employee manual booking + priest emergency override + refunds in production, (3) analytics answers the 3 pastoral questions in <1 min, (4) runbook + restore drill executed, (5) data-protection basics live (consent, export, delete, encrypted complaints, audit log).

- [ ] **Step 2: Verify each item**

Walk each item in production with the church liaison; check the box or record blocker + owner. Analytics verification script: priest logs into admin → Utilization shows current month per service → Payments shows paid/refunded totals → Bookings shows volume + status mix → each export downloads CSV.

- [ ] **Step 3: Handover**

Record owner assignments for: Paymob account, WhatsApp templates, YouTube channel, Supabase project, domain/DNS, app store credentials. Add to `docs/release/project-dod.md`.

- [ ] **Step 4: Commit**

```bash
git add docs/release/project-dod.md
git commit -m "docs(project): final DoD verification and handover"
```

---

*End of implementation plans. All phases reference the master blueprint; any future work (CMeeting replacement, multi-church, live streaming, AI assistant, NFC) goes through a new plan document.*
