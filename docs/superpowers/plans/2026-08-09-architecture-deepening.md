# Architecture Deepening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor Phase 0, 1 & 2 system seams to eliminate shallow pass-through Edge Functions, consolidate duplicated booking state machine transitions, and centralize RBAC security policies.

**Architecture:** Create an internal `transition_booking_status()` SQL RPC seam for booking status changes, centralize RLS policies into `is_admin_or_priest()` SQL helper functions, replace Web Crypto edge functions with PostgreSQL `pgcrypto` in-database encryption, and unify outbox tables into a single `event_outbox` & `event-dispatcher` edge function.

**Tech Stack:** Supabase (PostgreSQL 16, RLS, SECURITY DEFINER RPCs, pgcrypto, pg_cron), Deno Edge Functions, psql / pgTAP tests.

---

### Task 1: Unified Booking Transition Engine Seam (0026)

**Files:**
- Create: `supabase/migrations/0026_booking_transition_engine.sql`
- Test: `supabase/tests/0026_booking_transition_engine_test.sql`

- [ ] **Step 1: Write the failing test**

```sql
-- supabase/tests/0026_booking_transition_engine_test.sql
DO $$
DECLARE b_id bigint; st text;
BEGIN
  -- fixture
  INSERT INTO public.services (id, title_ar, tenant_id)
    VALUES (980, 'خدمة اختبار الترانزيشن', '00000000-0000-0000-0000-000000000001') ON CONFLICT DO NOTHING;
  INSERT INTO public.service_slots (id, service_id, starts_at, ends_at, capacity, price, tenant_id)
    VALUES (980, 980, now() + interval '1 day', now() + interval '1 day 2 hours', 10, 0, 1) ON CONFLICT DO NOTHING;
  INSERT INTO public.bookings (id, slot_id, user_id, status, tenant_id)
    VALUES (980, 980, (SELECT id FROM auth.users LIMIT 1), 'AWAITING_CALL', 1) ON CONFLICT DO NOTHING;

  -- Call central transition engine
  PERFORM public.transition_booking_status(980, 'CONFIRMED', 'تأكيد الروتين', (SELECT id FROM auth.users LIMIT 1));

  SELECT status::text INTO st FROM public.bookings WHERE id = 980;
  IF st != 'CONFIRMED' THEN
    RAISE EXCEPTION 'FAIL: booking status expected CONFIRMED, got %', st;
  END IF;

  -- Confirm audit log entry created
  IF NOT EXISTS (SELECT 1 FROM public.audit_log WHERE record_id = 980 AND action = 'UPDATE_STATUS') THEN
    RAISE EXCEPTION 'FAIL: audit log missing for status transition';
  END IF;

  RAISE NOTICE 'PASS: booking transition engine';
END $$;
```

- [ ] **Step 2: Run test, expect FAIL**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0026_booking_transition_engine_test.sql`
Expected: FAIL — function `transition_booking_status` does not exist.

- [ ] **Step 3: Minimal implementation**

```sql
-- supabase/migrations/0026_booking_transition_engine.sql
CREATE OR REPLACE FUNCTION public.transition_booking_status(
  p_booking_id bigint,
  p_new_status public.booking_status,
  p_reason text DEFAULT NULL,
  p_actor_id uuid DEFAULT auth.uid(),
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_old_status public.booking_status;
  v_slot_id bigint;
  v_user_id uuid;
BEGIN
  SELECT status, slot_id, user_id INTO v_old_status, v_slot_id, v_user_id
    FROM public.bookings WHERE id = p_booking_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Booking % does not exist', p_booking_id;
  END IF;

  IF v_old_status = p_new_status THEN
    RETURN; -- Idempotent no-op
  END IF;

  UPDATE public.bookings
    SET status = p_new_status, updated_at = now()
    WHERE id = p_booking_id;

  -- Insert centralized audit log entry
  INSERT INTO public.audit_log (table_name, record_id, action, old_data, new_data, actor_id, tenant_id)
    VALUES (
      'bookings',
      p_booking_id,
      'UPDATE_STATUS',
      jsonb_build_object('status', v_old_status),
      jsonb_build_object('status', p_new_status, 'reason', p_reason, 'metadata', p_metadata),
      p_actor_id,
      1
    );
END $$;
```

- [ ] **Step 4: Run test, expect PASS**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0026_booking_transition_engine_test.sql`
Expected: `NOTICE: PASS: booking transition engine`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0026_booking_transition_engine.sql supabase/tests/0026_booking_transition_engine_test.sql
git commit -m "refactor(booking): implement central transition_booking_status RPC seam"
```

---

### Task 2: RBAC Security Helper Seam (0027)

**Files:**
- Create: `supabase/migrations/0027_rbac_security_helpers.sql`
- Test: `supabase/tests/0027_rbac_security_helpers_test.sql`

- [ ] **Step 1: Write the failing test**

```sql
-- supabase/tests/0027_rbac_security_helpers_test.sql
DO $$
BEGIN
  SET ROLE anon;
  IF public.is_admin_or_priest() THEN
    RAISE EXCEPTION 'FAIL: anon identified as admin/priest';
  END IF;
  RESET ROLE;

  RAISE NOTICE 'PASS: rbac security helpers';
END $$;
```

- [ ] **Step 2: Run test, expect FAIL**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0027_rbac_security_helpers_test.sql`
Expected: FAIL — function `is_admin_or_priest` does not exist.

- [ ] **Step 3: Minimal implementation**

```sql
-- supabase/migrations/0027_rbac_security_helpers.sql
CREATE OR REPLACE FUNCTION public.is_admin_or_priest()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.current_user_role() IN ('ADMIN', 'PRIEST', 'SUPER_ADMIN');
$$;

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.current_user_role() = 'SUPER_ADMIN';
$$;

-- Refactor policies on analytics tables to use new helper seam
DROP POLICY IF EXISTS p_analytics_read_admin ON public.slot_utilization_monthly;
CREATE POLICY p_analytics_read_admin ON public.slot_utilization_monthly
  FOR SELECT USING (public.is_admin_or_priest());

DROP POLICY IF EXISTS p_analytics_read_admin ON public.payments_monthly;
CREATE POLICY p_analytics_read_admin ON public.payments_monthly
  FOR SELECT USING (public.is_admin_or_priest());

DROP POLICY IF EXISTS p_analytics_read_admin ON public.bookings_monthly;
CREATE POLICY p_analytics_read_admin ON public.bookings_monthly
  FOR SELECT USING (public.is_admin_or_priest());
```

- [ ] **Step 4: Run test, expect PASS**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0027_rbac_security_helpers_test.sql`
Expected: `NOTICE: PASS: rbac security helpers`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0027_rbac_security_helpers.sql supabase/tests/0027_rbac_security_helpers_test.sql
git commit -m "refactor(security): centralize RBAC policies behind is_admin_or_priest SQL helper seam"
```

---

### Task 3: In-Database Complaints pgcrypto Seam (0028)

**Files:**
- Create: `supabase/migrations/0028_complaints_pgcrypto.sql`
- Test: `supabase/tests/0028_complaints_pgcrypto_test.sql`

- [ ] **Step 1: Write the failing test**

```sql
-- supabase/tests/0028_complaints_pgcrypto_test.sql
DO $$
DECLARE c_id bigint; body_dec text;
BEGIN
  SELECT public.submit_complaint_secure('شكوى سرية اختبارية', NULL) INTO c_id;
  IF c_id IS NULL THEN
    RAISE EXCEPTION 'FAIL: complaint submission returned null';
  END IF;

  SELECT body INTO body_dec FROM public.v_decrypted_complaints WHERE id = c_id;
  IF body_dec != 'شكوى سرية اختبارية' THEN
    RAISE EXCEPTION 'FAIL: decrypted complaint body mismatch: %', body_dec;
  END IF;

  RAISE NOTICE 'PASS: complaints pgcrypto seam';
END $$;
```

- [ ] **Step 2: Run test, expect FAIL**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0028_complaints_pgcrypto_test.sql`
Expected: FAIL — function `submit_complaint_secure` does not exist.

- [ ] **Step 3: Minimal implementation**

```sql
-- supabase/migrations/0028_complaints_pgcrypto.sql
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.submit_complaint_secure(
  p_body text,
  p_assigned_priest_id uuid DEFAULT NULL
)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_id bigint;
  v_enc bytea;
  v_secret text := COALESCE(current_setting('app.complaints_key', true), 'default-church-secret-key-32b');
BEGIN
  v_enc := pgp_sym_encrypt(p_body, v_secret);

  INSERT INTO public.complaints (body_encrypted, assigned_priest_id, status, tenant_id)
    VALUES (v_enc, p_assigned_priest_id, 'NEW', 1)
    RETURNING id INTO v_id;

  RETURN v_id;
END $$;

CREATE OR REPLACE VIEW public.v_decrypted_complaints WITH (security_invoker = true) AS
SELECT
  c.id,
  c.created_at,
  c.status,
  c.assigned_priest_id,
  pgp_sym_decrypt(
    c.body_encrypted,
    COALESCE(current_setting('app.complaints_key', true), 'default-church-secret-key-32b')
  ) AS body
FROM public.complaints c;
```

- [ ] **Step 4: Run test, expect PASS**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0028_complaints_pgcrypto_test.sql`
Expected: `NOTICE: PASS: complaints pgcrypto seam`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0028_complaints_pgcrypto.sql supabase/tests/0028_complaints_pgcrypto_test.sql
git commit -m "refactor(complaints): replace edge functions with in-database pgcrypto RPC & view"
```

---

### Task 4: Unified Event Outbox & Dispatcher Seam (0029)

**Files:**
- Create: `supabase/migrations/0029_unified_event_outbox.sql`
- Create: `supabase/functions/event-dispatcher/index.ts`
- Create: `supabase/functions/event-dispatcher/index_test.ts`
- Test: `supabase/tests/0029_unified_event_outbox_test.sql`

- [ ] **Step 1: Write failing SQL test**

```sql
-- supabase/tests/0029_unified_event_outbox_test.sql
DO $$
DECLARE o_id bigint;
BEGIN
  INSERT INTO public.event_outbox (handler_type, payload)
    VALUES ('WHATSAPP', '{"phone": "+201000000000", "template": "booking_confirmed"}'::jsonb)
    RETURNING id INTO o_id;

  IF o_id IS NULL THEN
    RAISE EXCEPTION 'FAIL: event outbox insert failed';
  END IF;

  RAISE NOTICE 'PASS: unified event outbox';
END $$;
```

- [ ] **Step 2: Run test, expect FAIL**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0029_unified_event_outbox_test.sql`
Expected: FAIL — table `event_outbox` does not exist.

- [ ] **Step 3: Minimal implementation**

```sql
-- supabase/migrations/0029_unified_event_outbox.sql
CREATE TYPE public.event_handler_type AS ENUM ('WHATSAPP', 'PAYMOB_REFUND', 'FCM_PUSH', 'SMS');
CREATE TYPE public.outbox_status AS ENUM ('PENDING', 'PROCESSING', 'SENT', 'FAILED');

CREATE TABLE IF NOT EXISTS public.event_outbox (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  handler_type public.event_handler_type NOT NULL,
  payload jsonb NOT NULL,
  status public.outbox_status NOT NULL DEFAULT 'PENDING',
  attempts int NOT NULL DEFAULT 0,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz
);

ALTER TABLE public.event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_event_outbox_admin ON public.event_outbox
  FOR ALL USING (public.is_admin_or_priest());
```

`supabase/functions/event-dispatcher/index.ts`: Single Deno Edge Function fetching `PENDING` rows from `event_outbox`, invoking modular handler functions (`sendWhatsApp`, `triggerPaymobRefund`, `sendFcmPush`), and updating status with exponential backoff.

- [ ] **Step 4: Run test, expect PASS**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0029_unified_event_outbox_test.sql`
Expected: `NOTICE: PASS: unified event outbox`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0029_unified_event_outbox.sql supabase/tests/0029_unified_event_outbox_test.sql supabase/functions/event-dispatcher/
git commit -m "feat(outbox): introduce unified event_outbox table and event-dispatcher Edge Function"
```
