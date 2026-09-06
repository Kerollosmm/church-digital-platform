# Feature Specification: High-Concurrency Backend Remediation & Full Platform Route Wiring

**Feature Directory**: `specs/002-fix-concurrency-and-routing`  
**Feature Branch**: `002-fix-concurrency-and-routing`  
**Created**: 2026-08-14  
**Status**: Ready for Planning (`/speckit-plan`)  
**Input**: User description: `"start to plan to fix"` (remidiating backend concurrency bottlenecks, fixing admin/mobile route disconnects, and hardening RLS policies)

---

## 1. User Scenarios & Testing *(mandatory)*

### User Story 1 — Admin Web Secure Navigation & Authentication Guard (Priority: P1)

Church administrators, priests, and authorized staff accessing the Admin Web Dashboard must be intercepted at the application root and guided through the 3-step authentication sequence (Phone Number $\to$ WhatsApp OTP $\to$ Memorized PIN / First-Run PIN Setup) before accessing protected administrative screens (`/bookings`, `/manual-book`, `/emergency-override`, `/complaints`, `/analytics`, `/videos`). If an unauthenticated user attempts to access any admin URL directly, the system automatically redirects them to `/login`.

**Why this priority**: Shared parish computers and volunteer management terminals currently load administrative screens directly without enforcing the login gateway. Securing administrative routing with the 3-step PIN verification is essential to prevent unauthorized access to sensitive parish data.

**Independent Test**:
Can be fully tested by launching the admin web application at root `/`, verifying that the router immediately redirects to `/login` with the 3-step verification interface, completing the Phone $\to$ OTP $\to$ PIN flow, and verifying that navigation routes unlock and render the protected dashboard shell.

**Acceptance Scenarios**:
1. **Given** an unauthenticated admin opens any dashboard path (e.g. `/bookings` or `/analytics`), **When** the page initializes, **Then** the router redirects the browser to `/login`.
2. **Given** an admin enters a valid phone and WhatsApp OTP, **When** their account already has a memorized PIN, **Then** the UI requests their 4–6 digit PIN and grants dashboard access upon correct entry.
3. **Given** an admin enters a valid phone and OTP for the first time without a PIN set, **When** OTP verification succeeds, **Then** the UI presents the First-Run PIN Setup screen (PIN + Confirm PIN) and completes login upon confirmation.
4. **Given** an authenticated admin logs out or their session is locked after 5 failed attempts, **When** they attempt to navigate to a protected route, **Then** they are returned to `/login` with an informative Arabic lockout notice.

---

### User Story 2 — Parishioner Mobile Shell & Service Discovery Hub (Priority: P1)

Parishioners opening the mobile application must land on an interactive Arabic Home Hub featuring functional quick-action cards (Holy Mass, Confession, Event Booking, Spiritual Videos, Complaints) and an active 5-tab Bottom Navigation bar (`الرئيسية`, `الحجوزات`, `الفيديوهات`, `الشكاوى`, `حسابي`). Tapping any service or tab immediately transitions to the active feature screen without dead clicks or placeholder stubs.

**Why this priority**: The parishioner mobile app currently displays static service cards without click handlers and placeholder tabs, preventing parishioners from discovering church services, viewing video media, submitting complaints, or viewing their booked digital passes.

**Independent Test**:
Can be fully tested by launching the mobile app, tapping each quick-action card on the Home Hub, verifying navigation to the respective service screen or filter, and switching through all bottom navigation tabs to confirm active screens render without `ComingSoonTab` placeholders.

**Acceptance Scenarios**:
1. **Given** a parishioner is on the Home Hub, **When** they tap the "القداسات" (Mass) quick card, **Then** the app navigates to the Liturgy service catalog filtered for upcoming Holy Masses.
2. **Given** a parishioner is on the Home Hub, **When** they tap the "الفيديوهات" (Videos) or "الشكاوى" (Complaints) card, **Then** the app transitions directly to the respective feature screen.
3. **Given** a parishioner taps Tab 2 (`الفيديوهات`), Tab 3 (`الشكاوى`), or Tab 4 (`حسابي`), **Then** the app displays the active Video Purchase catalog, Complaints submission form, or My Bookings digital pass list respectively.
4. **Given** an unauthenticated parishioner taps "حجز" (Book) on an available slot, **When** the booking action triggers, **Then** the inline `PhoneVerifyGate` bottom sheet opens, verifies their WhatsApp OTP silently, and proceeds directly with the booking.

---

### User Story 3 — High-Concurrency Flash-Sale Atomic Reservation & Invariant Constraints (Priority: P1)

When hundreds or thousands of parishioners attempt to reserve seats for high-demand liturgical events (e.g. Easter Liturgy or summer retreat drops) at the exact same second, the booking engine executes atomic conditional inventory updates at the database core. The system guarantees that total confirmed plus reserved seats can never exceed the slot's physical capacity, without serializing transactions or creating lock contention queues.

**Why this priority**: High-demand church feast bookings cause severe traffic spikes. Relying on pessimistic table locks (`SELECT FOR UPDATE`) and runtime dynamic counts (`COUNT(*)`) causes database lock contention, timeout errors, and risks seat over-allocation under heavy concurrent load.

**Independent Test**:
Can be fully tested by running a high-concurrency simulation of 500 concurrent booking requests against a service slot with 50 available seats, asserting that exactly 50 reservations succeed, exactly 450 requests receive an immediate `SLOT_FULL` error response with zero retries, and remaining capacity never drops below 0.

**Acceptance Scenarios**:
1. **Given** a service slot with 10 remaining seats, **When** 20 concurrent reservation requests arrive simultaneously, **Then** the atomic conditional decrement confirms exactly 10 bookings and immediately rejects the remaining 10 with a deterministic `INVENTORY_EXHAUSTED` error in $<100\mu\text{s}$.
2. **Given** a service slot reaches 0 remaining capacity, **Then** the schema invariant `CHECK` constraint physically prevents any further decrements or negative seat balances.
3. **Given** an idempotent network retry with an existing idempotency key, **When** the reservation RPC executes, **Then** it returns the existing confirmed booking payload without deducting additional capacity.

---

### User Story 4 — Instant Real-Time Inventory Closure & Broadcast (Priority: P2)

When the final available seat of a service slot is reserved, the database immediately triggers a lightweight pub/sub broadcast notification over WebSocket channels. All connected client applications immediately update the slot state chip from `متاح` (Available) to `مكتمل` (Booked) without polling or overwhelming database replication streams.

**Why this priority**: Publishing high-frequency transactional write tables (`bookings`) to WAL CDC logical decoding forces PostgreSQL to evaluate Row-Level Security on every subscriber connection. Transitioning to targeted broadcast triggers eliminates replication lag and protects server CPU.

**Independent Test**:
Can be fully tested by subscribing two client devices to a slot's availability channel, completing the last seat booking on Device A, and asserting that Device B's UI updates its status chip to `مكتمل` within 100 milliseconds without reloading the page.

**Acceptance Scenarios**:
1. **Given** multiple parishioners are viewing the live slot grid, **When** the remaining capacity of a slot drops to 0, **Then** the database emits a `TIER_EXHAUSTED` / `SLOT_FULL` broadcast event.
2. **Given** client applications receive the exhaustion broadcast, **When** the event arrives, **Then** the slot card disables the booking CTA button in real time and presents the waiting list option.
3. **Given** high-volume booking writes occur, **Then** the write-heavy `bookings` table does not trigger logical CDC decoding passes across client subscribers.

---

### User Story 5 — Multi-Tenant RLS Subquery InitPlan Caching & Temporal Integrity (Priority: P2)

Parishioners and administrators querying event schedules and booking records experience constant sub-millisecond query response times through InitPlan-cached RLS policies and JWT custom claim validation. Simultaneously, church halls and altars are protected against temporal double-booking through spatial/temporal exclusion constraints.

**Why this priority**: Naked function calls like `auth.uid()` and table lookups inside RLS policies re-evaluate on every scanned row ($O(N)$ overhead). In addition, lack of temporal constraints allows accidental scheduling overlaps for the same altar or sanctuary hall.

**Independent Test**:
Can be fully tested by: (1) Running `EXPLAIN ANALYZE` on a large bookings query to verify InitPlan scalar subquery caching `(SELECT auth.uid())`, and (2) Attempting to insert two overlapping service slots for the same church hall and asserting that the database rejects the second slot via temporal exclusion constraint.

**Acceptance Scenarios**:
1. **Given** a parishioner queries their booking history across thousands of rows, **Then** RLS executes with InitPlan caching, evaluating authentication identity exactly once per query.
2. **Given** an administrator attempts to schedule a new Liturgy in "Altar 1" between 08:00 AM and 10:30 AM, **When** another active service is already scheduled in "Altar 1" between 09:00 AM and 11:00 AM, **Then** the database rejects the overlapping schedule with an exclusion violation.

---

### Edge Cases

- **Lock Expiration During Checkout**: A parishioner starts booking, holds a seat for 20 minutes, but fails to complete payment $\to$ The background expiry worker releases the lock, increments the slot's remaining capacity atomically, and triggers automatic waiting list promotion.
- **Simultaneous Last-Seat Contention**: Two parishioners submit a reservation for the 1 remaining seat at the same millisecond $\to$ The atomic `UPDATE ... WHERE remaining_capacity >= 1` succeeds for the first transaction and fails deterministically for the second without deadlock.
- **Admin PIN Lockout**: An unauthorized party attempts to guess an admin PIN 5 times consecutively $\to$ The account is locked for 15 minutes, the web UI displays an Arabic lockout banner, and the admin must complete a WhatsApp OTP challenge to reset the PIN.
- **Late Webhook Arrival on Expired Booking**: A payment provider webhook confirms payment after the 20-minute reservation has expired and been given to another parishioner $\to$ The payment transition engine marks the payment as `REFUND_PENDING` and enqueues an automated Paymob refund to the outbox.

---

## 2. Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST enforce an authentication redirect guard in the Admin Web App router, directing all unauthenticated visitors to `/login`.
- **FR-002**: System MUST render the complete 3-step authentication flow (Phone $\to$ WhatsApp OTP $\to$ Memorized PIN / First-Run PIN Setup) on the admin `/login` screen.
- **FR-003**: System MUST bind all Admin Shell navigation links (`/bookings`, `/manual-book`, `/emergency-override`, `/complaints`, `/analytics`, `/videos`) to functional view controllers and models.
- **FR-004**: System MUST wire mobile Home Hub quick action cards (`القداسات`, `الاعترافات`, `الحجوزات`, `الفيديوهات`, `الشكاوى`) with active navigation handlers.
- **FR-005**: System MUST configure `BottomNavScaffold` as the root mobile navigation shell with active tabs for Home, Services, Videos, Complaints, and My Bookings.
- **FR-006**: System MUST maintain an atomic `remaining_capacity` column on `service_slots` backed by a `CHECK (remaining_capacity >= 0)` constraint.
- **FR-007**: System MUST execute slot bookings via atomic conditional decrement (`UPDATE service_slots SET remaining_capacity = remaining_capacity - p_seats WHERE id = p_slot_id AND remaining_capacity >= p_seats`) without pessimistic table locks.
- **FR-008**: System MUST support idempotency keys on all booking RPCs to prevent double-charging or double-allocation on network retries.
- **FR-009**: System MUST restrict Supabase Realtime WAL CDC publication to low-frequency catalog tables and exclude high-frequency transactional `bookings` writes.
- **FR-010**: System MUST broadcast instant slot exhaustion notifications via database notification triggers over WebSocket channels.
- **FR-011**: System MUST wrap all RLS authentication identity functions in scalar subqueries `(SELECT auth.uid())` to enforce InitPlan execution plan caching.
- **FR-012**: System MUST extract user tenant identity and administrative roles directly from authenticated JWT custom claims (`app_metadata`).
- **FR-013**: System MUST enforce temporal non-overlapping constraints on service slots using `btree_gist` GiST exclusion constraints (`location WITH =, schedule_range WITH &&`).
- **FR-014**: System MUST decouple all third-party outbound communications (WhatsApp messages, push notifications, payment refunds) through the transactional `event_outbox` table and asynchronous Deno workers.
- **FR-015**: System MUST preserve an immutable append-only audit trail for all administrative state modifications (manual booking, emergency overrides, cancellations).

---

### Key Entities

- **Service Slot**: Represents a scheduled church gathering with title, date, `schedule_range` (`TSTZRANGE`), total capacity, `remaining_capacity`, pricing, church altar/location, and status (`OPEN`, `CLOSED`).
- **Booking**: An individual seat reservation linking a verified parishioner to a service slot with payment status (`PENDING_PAYMENT`, `AWAITING_CALL`, `CONFIRMED`, `COMPLETED`, `CANCELLED`, `RESCHEDULED`), seat count, and lock expiration.
- **Admin PIN Credential**: A cryptographic record storing Blowfish-hashed 4–6 digit PINs, consecutive failure counts, and temporal lockout timestamps for church staff.
- **Event Outbox Item**: A transactional message queue item storing outbound payloads (`WHATSAPP`, `FCM_PUSH`, `PAYMOB_REFUND`) with retry counts and backoff intervals.

---

## 3. Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of unauthenticated web requests to admin endpoints are blocked and redirected to the 3-step login interface before rendering dashboard data.
- **SC-002**: 100% of mobile Home Hub quick-action cards and bottom navigation tabs navigate directly to their active destination screens with zero placeholder screens.
- **SC-003**: The booking engine successfully processes 1,000 concurrent booking requests per second with **zero seat over-allocations** and $<100\text{ms}$ P95 latency.
- **SC-004**: Database CPU utilization under flash-sale booking bursts remains below 40% by eliminating WAL CDC RLS evaluation on the write-heavy `bookings` table.
- **SC-005**: All RLS policy evaluations execute in constant time $O(1)$ through InitPlan scalar subquery caching.
- **SC-006**: Zero venue or altar schedule overlap collisions occur across all scheduled church services.

---

## 4. Assumptions

- **Target Audience & Locale**: Primary users are Egyptian Coptic Orthodox parishioners and clergy using Arabic (RTL) interface conventions with Cairo typography.
- **Authentication Infrastructure**: Parishioner sessions are verified phone-first via WhatsApp OTP delivered by the `otp-sms` edge function without requiring user passwords.
- **Database Engine**: Backend operates on Supabase PostgreSQL 16 with `btree_gist`, `pgcrypto`, `pg_cron`, and `pg_net` extensions enabled.

---

## 5. Specification Quality Validation Checklist

```markdown
# Specification Quality Checklist: High-Concurrency Backend Remediation & Full Platform Route Wiring

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-14
**Feature**: specs/002-fix-concurrency-and-routing/spec.md

## Content Quality

- [x] No implementation details in user requirements (languages, frameworks, internal APIs avoided in user journeys)
- [x] Focused on user value and business needs
- [x] Written for business and church stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic
- [x] All acceptance scenarios are defined (Given / When / Then)
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary admin and parishioner flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] Ready for `/speckit-plan`
```

---

## 6. Completion Report

- **Feature Directory**: [`specs/002-fix-concurrency-and-routing`](file:///c:/church/specs/002-fix-concurrency-and-routing)
- **Specification File**: [`specs/002-fix-concurrency-and-routing/spec.md`](file:///c:/church/specs/002-fix-concurrency-and-routing/spec.md)
- **Checklist Summary**: All 16 validation items passed with 0 unresolved `[NEEDS CLARIFICATION]` items.
- **Readiness**: Ready to proceed directly to the planning phase via `/speckit-plan`.