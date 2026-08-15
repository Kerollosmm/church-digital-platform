# Implementation Plan: High-Concurrency Backend Remediation & Full Platform Route Wiring

**Branch**: `002-fix-concurrency-and-routing` | **Date**: 2026-08-14 | **Spec**: [`specs/002-fix-concurrency-and-routing/spec.md`](file:///c:/church/specs/002-fix-concurrency-and-routing/spec.md)

---

## 1. Summary

Remediate backend concurrency bottlenecks and fix front-end route disconnects across the Church Digital Platform. Transition the reservation engine from pessimistic row locks (`SELECT FOR UPDATE` + runtime `COUNT(*)`) to sub-millisecond **Atomic Conditional Updates** with database `CHECK` invariants. Replace high-overhead WAL CDC replication with **Realtime Pub/Sub Broadcast** triggers for inventory depletion. Wire the **Admin Web Router** with authentication guards and the 3-step PIN login flow, and connect the **Mobile App Navigation Shell** and Home Hub quick cards to active services and booking flows.

---

## 2. Technical Context

- **Frontend Stacks**: Flutter 3.x / Dart (Web + Mobile), Riverpod 2.x, GoRouter 14.x, `fl_chart`.
- **Backend Stack**: PostgreSQL 16 on Supabase (`pgcrypto`, `btree_gist`, `pg_cron`, `pg_net`), Deno Edge Functions (TypeScript).
- **Connection Topologies**: 
  - Mobile Client: Supavisor Transaction Mode (Port 6543, prepared statements OFF).
  - Admin Web: Supavisor Session Mode (Port 5432, prepared statements ON).
- **Test Harnesses**:
  - `apps/admin/`: `flutter test`
  - `apps/mobile/`: `flutter test`
  - `supabase/functions/`: `deno test --allow-env --allow-net`
  - `supabase/tests/`: `psql -f` regression suite
- **Performance Targets**: 1,000 concurrent booking requests/sec, P95 response $<100\text{ms}$, 0 seat over-allocations, zero Content Layout Shift ($\text{CLS} \le 0.05$).

---

## 3. Constitution & Architecture Quality Check

| Pillar / Rule | Status | Validation Strategy |
| :--- | :---: | :--- |
| **I. Atomic Concurrency Control** | 🟢 Pass | Conditional decrement `UPDATE ... WHERE remaining_capacity >= p_seats` + `CHECK (remaining_capacity >= 0)`. |
| **II. Realtime Broadcast Over CDC** | 🟢 Pass | Drop `bookings` from `supabase_realtime`; emit `pg_notify` on tier depletion. |
| **III. Ultra-Performant Multi-Tenant RLS** | 🟢 Pass | Scalar InitPlan caching `(SELECT auth.uid())` and JWT custom claim inspection. |
| **IV. Single-Writer Transition Engine** | 🟢 Pass | All status changes route strictly through `transition_booking_status`. |
| **V. Test-First (TDD Non-Negotiable)** | 🟢 Pass | Unit and integration tests written and failing before implementation. |

---

## 4. Project Structure & Changed Files

```text
specs/002-fix-concurrency-and-routing/
├── plan.md               # Master implementation plan
├── research.md           # Phase 0 architectural decisions & trade-offs
├── data-model.md         # Phase 1 schema, state machine & RPC specifications
├── quickstart.md         # Phase 1 verification runbook
└── contracts/
    ├── rpc-contracts.md      # Backend RPC interfaces & error codes
    └── router-contracts.md   # Web & Mobile GoRouter specifications

apps/
├── admin/
│   └── lib/
│       ├── app_router.dart                       # [EDIT] Add /login route + auth redirect guard
│       └── features/auth/admin_login_screen.dart # [EDIT] Integrate with GoRouter navigation
└── mobile/
    └── lib/
        ├── app_router.dart                       # [EDIT] Wire BottomNavScaffold as root shell
        ├── screens/home_hub_screen.dart          # [EDIT] Wire quick cards with active onTap handlers
        └── widgets/bottom_nav_scaffold.dart      # [EDIT] Connect Tabs 2, 3, 4 to active feature screens

supabase/
└── migrations/
    └── 0035_concurrency_hardening.sql           # [NEW] Atomic decrement, CHECK constraints, RLS InitPlan, GiST exclusion
```

---

# Phase 0: Research & Architectural Decisions

*Artifact: [`specs/002-fix-concurrency-and-routing/research.md`](file:///c:/church/specs/002-fix-concurrency-and-routing/research.md)*

### Decision 1: Atomic Conditional Decrement vs Pessimistic Locks
- **Decision**: Reject `SELECT FOR UPDATE` and runtime `COUNT(*)` in favor of single-statement conditional updates:
  ```sql
  UPDATE public.service_slots
  SET remaining_capacity = remaining_capacity - p_quantity,
      updated_at = clock_timestamp()
  WHERE id = p_slot_id AND remaining_capacity >= p_quantity
  RETURNING id, remaining_capacity, price;
  ```
- **Rationale**: Physical row locks are held for $<100\mu\text{s}$ at the database engine level. Eliminates lock queues, avoids connection pool exhaustion, and fails deterministically with zero retry storms.
- **Alternatives Considered**: 
  - *Optimistic Concurrency Control (OCC)*: Rejected due to catastrophic retry storms under 1000+ QPS.
  - *Pessimistic Locking (`SELECT FOR UPDATE`)*: Rejected due to lock serialization bottlenecks.

### Decision 2: Realtime Pub/Sub Broadcast vs Logical Decoding (WAL CDC)
- **Decision**: Remove write-heavy `public.bookings` from `supabase_realtime`. Implement database triggers emitting `pg_notify('realtime:event_inventory', ...)` on capacity exhaustion.
- **Rationale**: WAL CDC executes Row-Level Security on every connected client WebSocket per row insert. Realtime Broadcast operates via Phoenix memory channels ($>800\text{k}\text{ msgs/sec}$ at constant 30ms latency) without database CPU overhead.

### Decision 3: Admin Web Authentication Guard
- **Decision**: Bind `GoRouter(redirect: ...)` in [`apps/admin/lib/app_router.dart`](file:///c:/church/apps/admin/lib/app_router.dart) to listen to `adminAuthProvider`. Redirect unauthenticated sessions to `/login`.
- **Rationale**: Prevents direct URL access on shared church terminals and guarantees 100% 3-step PIN verification before mounting administrative widgets.

### Decision 4: Mobile Shell & Service Discovery Navigation
- **Decision**: Set `BottomNavScaffold` as the root route in [`apps/mobile/lib/app_router.dart`](file:///c:/church/apps/mobile/lib/app_router.dart), attach click handlers to `HomeHubScreen` quick cards, and replace `ComingSoonTab()` with `VideoPurchaseScreen`, `ComplaintsAdminScreen`/form, and `MyBookingsScreen`.
- **Rationale**: Restores full user journey connectivity from home discovery through booking and pass management.

---

# Phase 1: Data Model & Interface Contracts

*Artifact: [`specs/002-fix-concurrency-and-routing/data-model.md`](file:///c:/church/specs/002-fix-concurrency-and-routing/data-model.md)*

### Database Schema Updates (`0035_concurrency_hardening.sql`)

```sql
-- 1. Invariant capacity bound & schedule range
ALTER TABLE public.service_slots 
  ADD COLUMN IF NOT EXISTS remaining_capacity INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS schedule_range TSTZRANGE;

UPDATE public.service_slots 
SET remaining_capacity = GREATEST(capacity - public.active_booking_count(id), 0),
    schedule_range = tstzrange(starts_at, ends_at, '[)')
WHERE schedule_range IS NULL;

ALTER TABLE public.service_slots
  ADD CONSTRAINT check_remaining_capacity_non_negative CHECK (remaining_capacity >= 0),
  ADD CONSTRAINT check_schedule_valid CHECK (lower(schedule_range) < upper(schedule_range));

-- 2. Prevent overlapping altar/hall schedules
CREATE EXTENSION IF NOT EXISTS "btree_gist";

ALTER TABLE public.service_slots
ADD CONSTRAINT no_location_schedule_overlap
EXCLUDE USING GIST (
    location WITH =,
    schedule_range WITH &&
) WHERE (status <> 'CLOSED');

-- 3. Atomic Reservation RPC
CREATE OR REPLACE FUNCTION public.fn_book_slot_atomic(
    p_slot_id BIGINT,
    p_quantity INT DEFAULT 1,
    p_opt_in BOOLEAN DEFAULT FALSE,
    p_idempotency_key UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_slot RECORD;
    v_booking_id BIGINT;
    v_phone TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '28000'; END IF;
    IF p_quantity <= 0 OR p_quantity > 4 THEN RAISE EXCEPTION 'INVALID_QUANTITY' USING ERRCODE = '22023'; END IF;

    -- Idempotency check
    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_booking_id FROM public.bookings WHERE notes = p_idempotency_key::text;
        IF FOUND THEN
            RETURN jsonb_build_object('success', true, 'idempotent_replay', true, 'booking_id', v_booking_id);
        END IF;
    END IF;

    -- Atomic decrement (<100µs row lock)
    UPDATE public.service_slots
    SET remaining_capacity = remaining_capacity - p_quantity,
        updated_at = clock_timestamp()
    WHERE id = p_slot_id 
      AND status <> 'CLOSED' 
      AND starts_at > now()
      AND remaining_capacity >= p_quantity
    RETURNING id, price, remaining_capacity INTO v_slot;

    IF v_slot.id IS NULL THEN
        RAISE EXCEPTION 'INVENTORY_EXHAUSTED' USING ERRCODE = 'P0001';
    END IF;

    -- Create booking in single transaction
    INSERT INTO public.bookings (
        slot_id, user_id, status, paid_amount, locked_until, created_by, notes, tenant_id
    ) VALUES (
        p_slot_id, v_user, 'PENDING_PAYMENT', v_slot.price * p_quantity,
        now() + interval '20 minutes', 'system', p_idempotency_key::text, public.tenant_id()
    ) RETURNING id INTO v_booking_id;

    -- WhatsApp opt-in capture
    IF p_opt_in THEN
        SELECT phone INTO v_phone FROM public.users WHERE id = v_user;
        IF v_phone IS NOT NULL THEN
            INSERT INTO public.whatsapp_optins (phone, source) VALUES (v_phone, 'BOOKING')
            ON CONFLICT (phone) DO UPDATE SET consented_at = now();
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'booking_id', v_booking_id,
        'remaining_capacity', v_slot.remaining_capacity
    );
END;
$$;

-- 4. RLS InitPlan Scalar Subquery Optimizations
DROP POLICY IF EXISTS p0_bookings_read_own ON public.bookings;
CREATE POLICY p0_bookings_read_own ON public.bookings
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- 5. Realtime Depletion Broadcast Trigger
CREATE OR REPLACE FUNCTION public.fn_broadcast_slot_depletion()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public, pg_temp 
AS $$
BEGIN
    IF (OLD.remaining_capacity > 0 AND NEW.remaining_capacity = 0) THEN
        PERFORM pg_notify(
            'realtime:event_inventory',
            jsonb_build_object(
                'topic', 'slot:' || NEW.id::text || ':availability',
                'event', 'SLOT_EXHAUSTED',
                'payload', jsonb_build_object('slot_id', NEW.id, 'status', 'BOOKED')
            )::text
        );
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER tr_on_slot_depletion
AFTER UPDATE OF remaining_capacity ON public.service_slots
FOR EACH ROW WHEN (NEW.remaining_capacity = 0)
EXECUTE FUNCTION public.fn_broadcast_slot_depletion();
```

---

# Interface Contracts & Navigation Specifications

### 1. Backend RPC Contracts (`contracts/rpc-contracts.md`)

| RPC | Parameters | Return | Security / Access | Error Codes |
| :--- | :--- | :--- | :--- | :--- |
| `fn_book_slot_atomic` | `p_slot_id: BIGINT`, `p_quantity: INT`, `p_opt_in: BOOL`, `p_idempotency_key: UUID` | `JSONB` (`booking_id`, `remaining_capacity`) | `SECURITY DEFINER`, authenticated | `AUTH_REQUIRED` (28000), `INVENTORY_EXHAUSTED` (P0001), `INVALID_QUANTITY` (22023) |
| `verify_admin_pin` | `p_pin: TEXT` | `BOOLEAN` | `SECURITY DEFINER`, `is_admin()` | Returns `false` on failure / lockout |
| `set_admin_pin` | `p_pin: TEXT` | `VOID` | `SECURITY DEFINER`, `is_admin()` | `INVALID_PIN` (22023), `FORBIDDEN` (42501) |
| `admin_pin_status` | *None* | `TEXT` (`SET`, `UNSET`, `LOCKED`) | `SECURITY DEFINER`, `is_admin()` | `FORBIDDEN` (42501) |

### 2. Router Navigation Contracts (`contracts/router-contracts.md`)

#### Admin Web App Router (`apps/admin/lib/app_router.dart`)
- **Root Path `/`**: Redirects to `/bookings` if authenticated, else `/login`.
- **Public Route `/login`**: Renders `AdminLoginScreen` (Phone $\to$ OTP $\to$ PIN).
- **Protected Shell `/`**: Guards all child routes (`/bookings`, `/manual-book`, `/emergency-override`, `/complaints`, `/analytics`, `/videos`) via `redirect: (context, state)`:
  ```dart
  redirect: (context, state) {
    final authState = ref.read(adminAuthProvider);
    final loggingIn = state.uri.path == '/login';
    if (!authState.isAuthenticated) return loggingIn ? null : '/login';
    if (loggingIn) return '/bookings';
    return null;
  }
  ```

#### Parishioner Mobile App Router (`apps/mobile/lib/app_router.dart`)
- **Root Path `/`**: Renders `BottomNavScaffold`.
- **Tab 0 (`/home`)**: `HomeHubScreen` with active quick action cards.
- **Tab 1 (`/services`)**: `ServicesListScreen` $\to$ `SlotGridScreen` $\to$ `BookingDetailScreen`.
- **Tab 2 (`/videos`)**: `VideoPurchaseScreen`.
- **Tab 3 (`/complaints`)**: `ComplaintsFormScreen`.
- **Tab 4 (`/my-bookings`)**: `MyBookingsScreen` with digital pass QR view.

---

# Verification Runbook

*Artifact: [`specs/002-fix-concurrency-and-routing/quickstart.md`](file:///c:/church/specs/002-fix-concurrency-and-routing/quickstart.md)*

### Automated Test Gates

```bash
# 1. Admin Web Tests (Auth, Router Guard, Screens)
cd apps/admin
flutter test

# 2. Parishioner Mobile Tests (Home Navigation, BottomNav, PhoneGate)
cd ../mobile
flutter test

# 3. Deno Edge Functions Tests (OTP, Webhook HMAC, Outbox)
cd ../../supabase/functions
deno test --allow-env --allow-net

# 4. Backend Database Concurrency Regression
cd ..
psql $DATABASE_URL -f tests/run_all.sql
```

---

## 5. Completion Summary

- **Specification Directory**: [`specs/002-fix-concurrency-and-routing`](file:///c:/church/specs/002-fix-concurrency-and-routing)
- **Plan File**: [`specs/002-fix-concurrency-and-routing/plan.md`](file:///c:/church/specs/002-fix-concurrency-and-routing/plan.md)
- **Generated Artifacts**:
  - `research.md`: Concurrency & Realtime architecture decisions.
  - `data-model.md`: Migration 0035 schema, GiST exclusion, and atomic booking RPC.
  - `contracts/`: RPC and GoRouter interface specifications.
  - `quickstart.md`: Automated testing gates & verification runbook.
- **Ready for Next Step**: Proceed with `/speckit-tasks` to generate executable tracer-bullet implementation tasks.