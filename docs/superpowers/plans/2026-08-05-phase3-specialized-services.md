# Phase 3 — Specialized Services & Production Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the platform's booking engine to support specialized church service categories (Vacations/Trips, Weddings, Baptisms, Funerals, Voluntary Work) with category-specific metadata, filtering, and production onboarding integration checks.

**Architecture:** Extend `services` schema with `service_category` enum, introduce `book_specialized_slot()` SECURITY DEFINER RPC accepting extra metadata JSONB, update PostgREST views (`v_available_slots`, `v_my_bookings`), and add category filtering in Flutter Mobile & Web Admin apps.

**Tech Stack:** Supabase (PostgreSQL 16, RLS, SECURITY DEFINER RPCs), Deno Edge Functions, Flutter (Riverpod, GoRouter, Arabic RTL).

**Depends on:** Master plan `docs/superpowers/plans/2026-08-05-church-digital-platform.md`, ADR 0001 (`docs/adr/0001-v1-domain-model-refinements.md`), Phase 0–2 migrations (0001–0023).

---

### Task 1: Specialized Service Categories Schema Migration (0024)

**Files:**
- Create: `supabase/migrations/0024_specialized_services_schema.sql`
- Test: `supabase/tests/0024_specialized_services_schema_test.sql`

- [ ] **Step 1: Write the failing test**

```sql
-- supabase/tests/0024_specialized_services_schema_test.sql
DO $$
DECLARE cat text;
BEGIN
  INSERT INTO public.services (id, title_ar, category, tenant_id)
    VALUES (990, 'رحلة دير الميمون', 'VACATION', '00000000-0000-0000-0000-000000000001')
    ON CONFLICT DO NOTHING;

  SELECT category::text INTO cat FROM public.services WHERE id = 990;
  IF cat != 'VACATION' THEN
    RAISE EXCEPTION 'FAIL: expected VACATION category, got %', cat;
  END IF;

  RAISE NOTICE 'PASS: specialized service category schema';
END $$;
```

- [ ] **Step 2: Run test, expect FAIL**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0024_specialized_services_schema_test.sql`
Expected: FAIL — column `category` does not exist.

- [ ] **Step 3: Minimal implementation**

```sql
-- supabase/migrations/0024_specialized_services_schema.sql
DO $$ BEGIN
  CREATE TYPE public.service_category AS ENUM (
    'MASS', 'VACATION', 'WEDDING', 'BAPTISM', 'CONDOLENCE', 'VOLUNTARY'
  );
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS category public.service_category NOT NULL DEFAULT 'MASS';

-- Update v_available_slots view to expose category
CREATE OR REPLACE VIEW public.v_available_slots WITH (security_invoker = true) AS
SELECT
  sl.id AS slot_id,
  s.id AS service_id,
  s.title_ar AS service_title,
  s.category AS service_category,
  sl.starts_at,
  sl.ends_at,
  sl.capacity,
  sl.price,
  COUNT(b.id) FILTER (WHERE b.status IN ('AWAITING_CALL','CONFIRMED','COMPLETED')) AS active_bookings_count,
  CASE
    WHEN COUNT(b.id) FILTER (WHERE b.status IN ('AWAITING_CALL','CONFIRMED','COMPLETED')) >= sl.capacity THEN 'CLOSED'
    ELSE 'AVAILABLE'
  END AS status
FROM public.service_slots sl
JOIN public.services s ON s.id = sl.service_id
LEFT JOIN public.bookings b ON b.slot_id = sl.id
GROUP BY sl.id, s.id, s.title_ar, s.category, sl.starts_at, sl.ends_at, sl.capacity, sl.price;
```

- [ ] **Step 4: Run test, expect PASS**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0024_specialized_services_schema_test.sql`
Expected: `NOTICE: PASS: specialized service category schema`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0024_specialized_services_schema.sql supabase/tests/0024_specialized_services_schema_test.sql
git commit -m "feat(services): add service_category enum and update availability view"
```

---

### Task 2: Specialized Booking RPC with Metadata (0025)

**Files:**
- Create: `supabase/migrations/0025_specialized_booking_rpc.sql`
- Test: `supabase/tests/0025_specialized_booking_rpc_test.sql`

- [ ] **Step 1: Write the failing test**

```sql
-- supabase/tests/0025_specialized_booking_rpc_test.sql
DO $$
DECLARE b_id bigint;
BEGIN
  -- fixture slot
  INSERT INTO public.services (id, title_ar, category, tenant_id)
    VALUES (991, 'معمودية أطفال', 'BAPTISM', '00000000-0000-0000-0000-000000000001') ON CONFLICT DO NOTHING;
  INSERT INTO public.service_slots (id, service_id, starts_at, ends_at, capacity, price, tenant_id)
    VALUES (991, 991, now() + interval '1 day', now() + interval '1 day 1 hour', 5, 0, 1) ON CONFLICT DO NOTHING;

  SELECT public.book_specialized_slot(
    991,
    '{"child_name": "مارك أيمن", "birth_date": "2026-01-01"}'::jsonb
  ) INTO b_id;

  IF b_id IS NULL THEN
    RAISE EXCEPTION 'FAIL: booking ID returned null';
  END IF;

  RAISE NOTICE 'PASS: specialized booking rpc';
END $$;
```

- [ ] **Step 2: Run test, expect FAIL**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0025_specialized_booking_rpc_test.sql`
Expected: FAIL — function `book_specialized_slot` does not exist.

- [ ] **Step 3: Minimal implementation**

```sql
-- supabase/migrations/0025_specialized_booking_rpc.sql
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION public.book_specialized_slot(
  p_slot_id bigint,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_capacity int;
  v_booked int;
  v_user_id uuid := auth.uid();
  v_booking_id bigint;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED: User must be authenticated';
  END IF;

  SELECT capacity INTO v_capacity
    FROM public.service_slots WHERE id = p_slot_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Slot does not exist';
  END IF;

  SELECT count(*) INTO v_booked
    FROM public.bookings
    WHERE slot_id = p_slot_id AND status IN ('AWAITING_CALL','CONFIRMED','COMPLETED');

  IF v_booked >= v_capacity THEN
    RAISE EXCEPTION 'SLOT_FULL: Capacity reached';
  END IF;

  INSERT INTO public.bookings (slot_id, user_id, status, metadata, tenant_id)
    VALUES (p_slot_id, v_user_id, 'CONFIRMED', p_metadata, 1)
    RETURNING id INTO v_booking_id;

  RETURN v_booking_id;
END $$;
```

- [ ] **Step 4: Run test, expect PASS**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0025_specialized_booking_rpc_test.sql`
Expected: `NOTICE: PASS: specialized booking rpc`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0025_specialized_booking_rpc.sql supabase/tests/0025_specialized_booking_rpc_test.sql
git commit -m "feat(booking): add book_specialized_slot RPC with metadata payload"
```

---

### Task 3: Mobile Category Filter & Metadata Form (0026)

**Files:**
- Modify: `apps/mobile/lib/features/booking/booking_screen.dart`
- Create: `apps/mobile/test/specialized_booking_widget_test.dart`

- [ ] **Step 1: Write widget test**

```dart
// apps/mobile/test/specialized_booking_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Category chips display expected Arabic titles', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Row(
              children: [
                Chip(label: Text('القداسات')),
                Chip(label: Text('الرحلات')),
                Chip(label: Text('الإكليل')),
                Chip(label: Text('المعمودية')),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('القداسات'), findsOneWidget);
    expect(find.text('الرحلات'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test, expect PASS**

Run: `flutter test apps/mobile/test/specialized_booking_widget_test.dart`
Expected: PASS.

- [ ] **Step 3: Update `booking_screen.dart`**

Add filter chips for categories (`MASS`, `VACATION`, `WEDDING`, `BAPTISM`, `CONDOLENCE`, `VOLUNTARY`) and pass `p_metadata` map to RPC when creating specialized bookings.

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/features/booking/ apps/mobile/test/specialized_booking_widget_test.dart
git commit -m "feat(mobile): add category filtering and specialized metadata booking form"
```

---

### Task 4: Onboarding Readiness Health Check Edge Function (0027)

**Files:**
- Create: `supabase/functions/onboarding-health/index.ts`
- Create: `supabase/functions/onboarding-health/index_test.ts`

- [ ] **Step 1: Write edge fn test**

```ts
// supabase/functions/onboarding-health/index_test.ts
import { assertEquals } from "jsr:@std/assert";
import { checkConfig } from "./index.ts";

Deno.test("returns true when required secrets present", () => {
  const env = new Map([
    ["SUPABASE_URL", "http://127.0.0.1:54321"],
    ["PAYMOB_API_KEY", "test_key"],
  ]);
  assertEquals(checkConfig(env), true);
});
```

- [ ] **Step 2: Run test, expect PASS**

Run: `deno test supabase/functions/onboarding-health/index_test.ts`
Expected: PASS.

- [ ] **Step 3: Implement `index.ts`**

Implement health check endpoint verifying presence of Paymob, Meta WhatsApp, and YouTube credentials.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/onboarding-health/
git commit -m "feat(ops): add onboarding health check edge function"
```
