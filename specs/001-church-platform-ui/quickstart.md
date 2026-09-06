# Phase 1: Quickstart Validation Guide

### Scenario 1: Parishioner Multi-Seat Booking (P1)
1. Launch parishioner mobile app in Arabic RTL mode.
2. Select upcoming Holy Liturgy slot (e.g., Friday Mass, 150 capacity).
3. Select 3 seats and input Head of Household name ("جرجس مرقص").
4. Tap confirm; verify booking state transitions to `CONFIRMED`.
5. Turn on Airplane Mode; verify reservation pass renders cached QR code and 4-character entry code.

### Scenario 2: Admin 3-Step Authentication Flow (P1)
1. Open Admin Web portal (`/admin/login`).
2. Complete Step 1: Email/Password login.
3. Complete Step 2: SMS/WhatsApp OTP code entry.
4. Complete Step 3: Enter 6-digit Admin Security PIN.
5. Verify access to Admin Dashboard with Realtime booking count stream.

### Scenario 3: Static Analysis & Code Quality
```bash
# Mobile unit & widget tests
flutter test apps/mobile/test

# Admin portal unit & component tests
flutter test apps/admin/test

# Dart analyzer
flutter analyze apps/mobile apps/admin
```
