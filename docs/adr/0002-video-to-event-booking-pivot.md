# ADR 0002: Pivot from Video Payments to Event Booking with Extra Services

- **Status**: accepted
- **Date**: 2026-08-19

## Context

On 2026-08-17, product ownership made a core architectural decision to cancel and decommission all personal filmed-video sales and video catalog payment features. The original video catalog and per-booking video delivery workflows created operational complexity without matching parish needs.

## Decision

1. **Decommission Video Machinery**:
   - Dropped `videos` and `video_purchases` tables.
   - Removed `video_id` foreign keys and columns from `payments`.
   - Removed RPCs: `purchase_video`, `apply_video_payment`, and `deliver_personal_video`.
   - Dropped orphan `video_privacy` enum type (`0062_drop_video_privacy_enum.sql`).

2. **Active Replacement — Event Booking with Extra Services (Specs 007 & 008)**:
   - Separate domain entities: `event_types` and `extra_services`.
   - Venue and resource scheduling integrity via GiST temporal exclusion constraints `(resource_id, tstzrange)`.
   - Review-first-then-pay lifecycle: `SUBMITTED → CONFIRMED/REJECTED → PENDING_PAYMENT → PAID`.
   - Immutable price snapshotting on selected extras at reservation time.
   - Dual payment rail support: Paymob online checkout + administrative cash collection RPCs.

## Consequences

- Constitution is updated to version 1.1.0 reflecting Event Booking with Extra Services as active product truth.
- Zero remaining video database objects or RPCs in production database schema.
