# Cross-Repository Architectural Audit & Key Learnings
**Auditor Persona:** Principal Supabase Backend Architect (`supabase-backend-architect`)  
**Target Project:** Egyptian Coptic Church Digital Platform (`C:\church`)  
**Reference Repositories Analyzed:**
1. [`flutter-hotel-booking-app`](file:///C:/Users/KimoStore/Downloads/flutter-hotel-booking-app-main/flutter-hotel-booking-app-main)
2. [`festapp-main`](file:///C:/Users/KimoStore/Downloads/festapp-main/festapp-main)

---

## 1. Executive Comparison Matrix

| Architectural Dimension | 🏨 Hotel Booking App | 🎪 Festapp | ⛪ Church Digital Platform | Best Practice Recommendation |
| :--- | :--- | :--- | :--- | :--- |
| **Concurrency Control** | ❌ Multi-step client check + raw table insert (TOCTOU race condition) | ❌ Non-atomic Check-Then-Act in SQL (`SELECT count` without row locks) | ✅ Atomic `SECURITY DEFINER` RPCs (`book_slot`) with `SELECT ... FOR UPDATE` + CHECK constraints | **Mandatory Church Standard**: Zero-trust server-side atomic locking. |
| **Multi-Tenancy & RBAC** | ❌ Table-level disk subqueries (`EXISTS (SELECT 1 FROM profiles WHERE ...)`) | ❌ Nested subqueries calling helper SQL functions per row | ✅ Fast JWT `app_metadata` custom claims + InitPlan caching `(SELECT auth.uid())` | **Church Standard**: Eliminate $O(N)$ row-level disk lookups in RLS. |
| **Offline Capabilities** | ❌ Online only (fails on poor connection) | ✅ **Sembast NoSQL local DB + MBTiles vector maps** + bundle sync | ⚠️ Direct connection only in v1 (network-dependent) | **Adopt Festapp Pattern**: Offline read cache for QR ticket codes & liturgy schedules in dead-zone church basements. |
| **State Mutations & Integrity** | ❌ Raw client `UPDATE` / `INSERT` on bookings table | ❌ Direct SQL updates without transactional outbox | ✅ Strict SQL state transitions + append-only audit trigger + `event_outbox` / `pgmq` | **Church Standard**: Guard state changes with cryptographic audit trail & async dispatch. |
| **UI Modular Architecture** | ✅ Clean role-based folder hierarchy (`admin/`, `manager/`, `user/`, `shared/`) | ❌ Monolithic mix of admin & user UI in one mobile bundle + separate vanilla JS client | ✅ Monorepo app separation: `apps/mobile/` (Parishioner Flutter) & `apps/admin/` (Staff Flutter Web) | **Adopt Hotel App Directory Pattern**: Role-scoped UI folders inside clean architecture. |
| **Family / Companion Booking** | ❌ Single guest per booking row | ✅ `user_companions` table allowing one account to register family members | ⚠️ Primary user single-seat booking | **Adopt Festapp Feature**: Companion / family member booking table for liturgy feast reservations. |

---

## 2. Deep Dive: `flutter-hotel-booking-app`

### 2.1 Strengths & Reusable Patterns
1. **Clean Role-Based Screen Hierarchy**:
   - Organized screens cleanly by actor: `lib/screens/user/`, `lib/screens/manager/`, `lib/screens/admin/`, `lib/screens/auth/`, `lib/screens/shared/`.
   - Makes navigation guards and permission-based routing in GoRouter easy to understand and maintain.
2. **Date Range Free/Busy Gap Finding**:
   - `BookingService._findFreeRanges` in Dart accurately computes available sub-intervals between booked dates for clean calendar rendering.

### 2.2 Critical Vulnerabilities & Anti-Patterns to Avoid
1. **Time-of-Check to Time-of-Use (TOCTOU) Race Condition**:
   - The app checks booked room IDs via RPC `get_booked_room_ids`, then sends a separate `_client.from('bookings').insert(...)`.
   - **Why it breaks**: If two users view availability simultaneously, both see the room open and both insert booking rows, leading to double-booking.
2. **Subquery Cascades in RLS**:
   - Policies like `create policy "Admin can manage rooms" on rooms using (exists (select 1 from profiles where profiles.id = auth.uid() and profiles.role = 'admin'))` cause PostgreSQL to scan the `profiles` table for every single evaluated row.
3. **Client-Driven Business Logic**:
   - Refund calculations and cancellation status updates happen client-side without cryptographic verification or server validation.

---

## 3. Deep Dive: `festapp-main`

### 3.1 Strengths & Reusable Patterns
1. **Robust Offline-First Architecture**:
   - Utilizes `Sembast` (embedded NoSQL database) in `StorageHelper` to cache events, news, info pages, places, and user inventory.
   - `SynchroService.refreshOfflineData()` pulls complete bundles for seamless offline browsing during network blackouts.
   - Saves vector map tiles locally for offline event navigation.
2. **Companion / Family Booking Model (`user_companions`)**:
   - Allows a registered attendee to manage sub-profiles for family members and book multiple workshop spots under one master account.
3. **Feature Flagging in Schema**:
   - Uses `occasions.features` (JSONB) to dynamically toggle modules (e.g. food tickets, workshops, maps, eshop).

### 3.2 Critical Vulnerabilities & Anti-Patterns to Avoid
1. **Non-Atomic Capacity Verification in SQL**:
   - In `sign_user_to_event.sql`, the function does `SELECT count(*) INTO current_participants; IF current_participants >= max THEN RETURN ... ELSE INSERT ...`.
   - **Why it breaks**: Under concurrent registration spikes, multiple transactions read `current_participants < max` at the same time and all proceed to insert, breaching the venue capacity.
2. **Seat Overwrite Race Conditions**:
   - In `select_spot.sql`, the `UPDATE eshop.spots SET secret = secret_id ... WHERE id = spot_id` lacks a conditional guard `AND (secret IS NULL OR secret_expiration_time < now())`, allowing concurrent users to overwrite each other's locked seats.
3. **Monolithic Bundle Bloat**:
   - Bundling admin and organizer tools into the mobile client inflated app size, requiring the authors to write a separate vanilla JS web client.

---

## 4. Key Learnings & Enhancements for Church Digital Platform

### Lesson 1: Implement an Offline Read Cache for Church Basements
- **Problem**: Egyptian Coptic church buildings feature thick reinforced concrete and stone walls; basement sanctuaries frequently have zero cellular coverage.
- **Solution**: Adopt Festapp's offline caching pattern in `apps/mobile/`. Cache `v_my_bookings` (QR ticket codes) and mass schedules in local storage so parishioners can display entry passes offline.

### Lesson 2: Support Family Member Booking
- **Problem**: In church liturgies, parents book seats for their children, spouses, or elderly parents who do not possess smartphones.
- **Solution**: Adopt Festapp's `user_companions` model. Implement `family_companions` table and `book_family_slot()` RPC to reserve multiple seats in a single atomic transaction.

### Lesson 3: Enforce Strict Zero-Trust Backend Invariants
- **Confirmation**: Both reference repos demonstrated how easy it is to introduce double-booking race conditions through client-side checks or flawed `SELECT count(*)` SQL logic.
- **Church Enforcement**: Never rely on client checks. Enforce server-side `SELECT ... FOR UPDATE` on `service_slots` + schema `CHECK` constraints + Supavisor Transaction Pooler (port 6543) during feast registration spikes (300 QPS).

### Lesson 4: Maintain Clean Separation in Monorepo
- **Confirmation**: Festapp suffered from mixing admin features into the attendee mobile app.
- **Church Enforcement**: Keep `apps/mobile/` (Parishioner Flutter Mobile) and `apps/admin/` (Staff Flutter Web PWA) completely segregated.

### Lesson 5: Outbox Pattern is Essential for Reliability
- **Confirmation**: Both reference repos attempted direct HTTP calls or manual screenshot verifications.
- **Church Enforcement**: Maintain transactional `event_outbox` drained by Deno Edge Functions and `pg_cron` for Paymob webhook verification, WhatsApp Meta Graph API dispatches, and FCM push notifications.
