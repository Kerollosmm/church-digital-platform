# Original User Request

## 2026-08-19T19:52:13Z

Build lightweight, fully functional HTML/JS web test harnesses connecting to local/remote Supabase backend for end-to-end verification of all platform features across User, Admin, and SuperAdmin roles.

Working directory: c:\church\test_harness

## Requirements

### R1. User Test Web App (user.html / user.js)
- Phone OTP / Email auth login & registration.
- Profile view & update.
- Browse services, view available slot capacity (_available_slots).
- Book service slot (ook_slot RPC) with seat count and form submission.
- Browse event types & extra services, submit event booking (SUBMITTED).
- View user booking history & real-time status transitions (AWAITING_CALL, CONFIRMED, PENDING_PAYMENT, PAID).
- Mock checkout / payment simulation (pply_payment RPC) for paid bookings.

### R2. Admin Test Web App (dmin.html / dmin.js)
- Admin auth check (enforce ADMIN or PRIEST role).
- Booking Confirmation Call workbench: list AWAITING_CALL bookings, trigger 	ransition_booking_status to CONFIRMED or REJECTED.
- Manage service slots (create/edit capacity, date range).
- Review event bookings: confirm/reject requests, calculate pricing with extra services.
- Record manual cash payments via Admin RPC.
- View live attendance / check-in dashboard.

### R3. SuperAdmin Test Web App (superadmin.html / superadmin.js)
- SuperAdmin auth guard (SUPER_ADMIN role).
- Manage church settings, users & role elevations (USER -> ADMIN / PRIEST).
- Outbox inspection & manual trigger (whatsapp_outbox processing).
- System audit log viewer & error message catalog management.

### R4. Shared Config & Live Supabase Client
- Single shared configuration (config.js) for Supabase URL + Anon Key.
- Realtime subscription handling for live state updates on bookings and notifications.

## Acceptance Criteria

### Authentication & RBAC Guardrails
- [ ] User role cannot access Admin or SuperAdmin RPCs / tables (RLS enforcement verified).
- [ ] Admin role can transition booking states but cannot elevate user roles.
- [ ] SuperAdmin can manage system configuration and role assignments.

### Functional End-to-End Flow
- [ ] Complete User Flow: Auth → Slot check → ook_slot → AWAITING_CALL state.
- [ ] Complete Admin Flow: Admin views booking → confirms call → marks CONFIRMED → User sees live status change.
- [ ] Complete Event + Extras Flow: User submits event with selected extras → Admin reviews & approves → User completes payment.
