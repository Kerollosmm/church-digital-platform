# Event Booking Extra Services: Pivot & 25 Binding Decisions

## Context of the Pivot (2026-08-17)
The personal filmed-video payment feature was cancelled outright. The tables `videos` and `video_purchases` had zero production data. 
The church's actual operational requirement is **Event Booking with Extra Services** (weddings, engagements, baptisms, funerals) with configurable priced add-on services (photography, decorations, chairs, sound system).

Work was split into two sequential specifications:
- **Spec 007**: Backend Security and Correctness Fixes (decommission video, harden RPCs/RLS).
- **Spec 008**: Event Booking Extra Services (schema, RPCs, multi-payment, Flutter UI).

---

## 25 Binding Decisions (Authoritative — Do Not Re-litigate)

### Architecture & Security Foundations
1. **RPC-Only Writes**: Direct client DML on sensitive tables (`payments`, `complaints`, `users`, `audit_log`, `roles_permissions`) is revoked. All mutations go through `SECURITY DEFINER` RPCs.
2. **`apply_payment` is `service_role` Only**: Only Paymob webhooks and the reconcile cron may invoke payment confirmation. Clients never confirm their own payments.
3. **App Roles**: `app_role` enum contains `USER`, `ADMIN`, `SUPER_ADMIN`. All legacy `PRIEST` references are purged.
4. **Failed WhatsApp Resend**: Failed message deliveries surface in an admin backlog view (`v_failed_outbox_events`) with an explicit staff resend action (`admin_resend_outbox_event`).

### Video Decommissioning
5. **Total Removal of Video System**: Complete removal of `videos`, `video_purchases`, `purchase_video`, `apply_video_payment`, `deliver_personal_video`, `payments.video_id`, `youtube-expiry` edge function/cron, and mobile/admin video screens.

### Event Model & Venue Scheduling
6. **Separate `event_types` Table**: Distinct from regular recurring `services`/`service_slots`. Events are appointment reservations with resource/time conflict checks.
7. **Resource & Venue Exclusion Constraints**: Tables for venues/resources enforce PostgreSQL exclusion constraints on `(resource_id, tstzrange)` using `btree_gist` to prevent double-booking at DB level.
8. **Review-First, Pay-Later Lifecycle**: Parishioner submits request -> Admin reviews and confirms/rejects -> Parishioner pays online or Admin records cash. No payment is accepted on unconfirmed requests.
9. **Partial Payments & Mixed Methods**: Multiple payments per booking are supported (online Paymob + manual cash). Booking tracks total and outstanding balance.
10. **Extended Payments Ledger & Audit Logs**: `payments` table supports `method` (`ONLINE`/`CASH`), `recorded_by`, `received_at`, `receipt_reference`, and immutable `payment_audit_logs`.

### Packaging & Process
11. **Two-Spec Split**: Spec 007 (security fixes & video removal) lands first; Spec 008 (event booking) builds on top.
12. **004 Work Clean Commit**: Feature 004 committed cleanly without mixing unrelated mobile/admin edits.
13. **Superseded Specs**: Specs `005-admin-domain-layer` and `006-mobile-domain-layer` are deleted and folded into 008.
14. **pgTAP Testing**: pgTAP suites for new features; plain assert suites maintained in parallel.
15. **Multi-Session Concurrency Verification**: Real multi-session tests via `dblink` for lock contention, payment idempotency, and outbox drain.

### Financials & Service Rules
16. **Monetary Unit in Piastres**: All prices and amounts are stored as integer piastres (1 EGP = 100). No float/numeric precision issues.
17. **Mixed Quantity Model, No Stock Tracking**: Extra services are either fixed single selections (`quantity = 1`, e.g. photography) or quantity-based (e.g. chairs). No inventory tracking — admin verifies availability at confirmation.
18. **Admin Assigns Venue at Confirmation**: Parishioner submits event type, extras, and preferred time; Admin selects and assigns the venue during `admin_confirm_booking`.
19. **Dual Cash Permissions**: Both `ADMIN` and `SUPER_ADMIN` can record cash payments via `admin_record_cash_payment`. Every call is audited with `recorded_by`.
20. **Mandatory Rejection Reasons**: `admin_reject_booking` requires a non-empty explanation, stored on the booking, logged to audit, and sent to the parishioner via WhatsApp.
21. **Four Event WhatsApp Templates**: 
   - Submission received
   - Booking confirmed (venue, time, total, payment link)
   - Booking rejected (with reason)
   - Payment received / balance due
22. **Unified Booking State Machine**: Status enum extended with `SUBMITTED` and `REJECTED`.
23. **Cash & Online Refunds**: Online refunds use `mark_payment_refunded` + outbox; cash refunds recorded as negative adjustments via `SUPER_ADMIN` RPC.
24. **Documented Multi-Tenant Shortcut**: `tenant_id()` fallback to `'1'` is preserved and documented as internal single-church scaffolding.
25. **Derived Slot Availability**: Dropped `remaining_capacity` counter column; availability is derived dynamically from active bookings to prevent counter drift.
