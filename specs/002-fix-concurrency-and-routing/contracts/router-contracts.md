# Router Navigation Contracts

### Admin Web App Router (`apps/admin/lib/app_router.dart`)
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

### Parishioner Mobile App Router (`apps/mobile/lib/app_router.dart`)
- **Root Path `/`**: Renders `BottomNavScaffold`.
- **Tab 0 (`/home`)**: `HomeHubScreen` with active quick action cards.
- **Tab 1 (`/services`)**: `ServicesListScreen` $\to$ `SlotGridScreen` $\to$ `BookingDetailScreen`.
- **Tab 2 (`/videos`)**: `VideoPurchaseScreen`.
- **Tab 3 (`/complaints`)**: `ComplaintsFormScreen`.
- **Tab 4 (`/my-bookings`)**: `MyBookingsScreen` with digital pass QR view.
```

---