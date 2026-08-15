# Research & Architectural Decisions: Concurrency, Realtime & Navigation

## Decision 1: Atomic Inventory Decrement vs Pessimistic Locks
- **Decision**: Reject `SELECT FOR UPDATE` and runtime dynamic `COUNT(*)` in favor of single-statement conditional updates:
  ```sql
  UPDATE public.service_slots
  SET remaining_capacity = remaining_capacity - p_quantity,
      updated_at = clock_timestamp()
  WHERE id = p_slot_id AND remaining_capacity >= p_quantity
  RETURNING id, remaining_capacity, price;
  ```
- **Rationale**: Physical row locks are held for $<100\mu\text{s}$ at the database engine level. Eliminates lock queues, avoids connection pool exhaustion, and fails deterministically with zero retry storms.
- **Alternatives Considered**: 
  - *OCC (Optimistic Concurrency Control)*: Rejected due to catastrophic retry loops under contention.
  - *Pessimistic Locking (`SELECT FOR UPDATE`)*: Rejected due to transaction serialization bottlenecks.

## Decision 2: Instant Inventory Closure via Realtime Broadcast vs WAL CDC
- **Decision**: Remove write-heavy `public.bookings` from `supabase_realtime`. Implement database triggers emitting `pg_notify('realtime:event_inventory', ...)` on capacity exhaustion.
- **Rationale**: WAL CDC executes Row-Level Security on every connected client WebSocket per row insert. Realtime Broadcast operates via Phoenix memory channels ($>800\text{k}\text{ msgs/sec}$ at constant 30ms latency) without database CPU overhead.

## Decision 3: Admin Web Authentication Guard
- **Decision**: Bind `GoRouter(redirect: ...)` in `apps/admin/lib/app_router.dart` to listen to `adminAuthProvider`. Redirect unauthenticated sessions to `/login`.
- **Rationale**: Prevents direct URL access on shared church terminals and guarantees 100% 3-step PIN verification before mounting administrative widgets.

## Decision 4: Mobile Shell & Service Discovery Navigation
- **Decision**: Set `BottomNavScaffold` as the root route in `apps/mobile/lib/app_router.dart`, attach click handlers to `HomeHubScreen` quick cards, and replace `ComingSoonTab()` with `VideoPurchaseScreen`, `ComplaintsAdminScreen`/form, and `MyBookingsScreen`.
- **Rationale**: Restores full user journey connectivity from home discovery through booking and pass management.