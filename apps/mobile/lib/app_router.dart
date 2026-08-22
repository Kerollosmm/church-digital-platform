import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/auth/auth_gateway.dart';
import 'features/booking/payment_proof_screen.dart';
import 'features/booking/payment_redirect_screen.dart';
import 'features/complaints/complaints_repository.dart';
import 'features/portal/portal_repository.dart';
import 'repositories/supabase_booking_repository.dart';
import 'services/app_routes.dart';
import 'services/app_supabase.dart';
import 'widgets/bottom_nav_scaffold.dart';

GoRoute paymentRedirectRoute(AppSupabase db) {
  final bookings = SupabaseBookingRepository(db);
  return GoRoute(
    path: '/payment-redirect',
    name: AppRoutes.paymentRedirect,
    builder: (context, state) {
      final extra = state.extra;
      if (extra is Map) {
        final bookingId = (extra['bookingId'] ?? extra['booking_id'] ?? extra['payment_id'] ?? 0) as int;
        final checkoutUrl = (extra['checkoutUrl'] ?? extra['checkout_url']) as String?;
        return PaymentRedirectScreen(
          bookingId: bookingId,
          checkoutUrl: checkoutUrl,
          onRetryCheckout: (id) => bookings.retryCheckout(id),
        );
      }
      if (extra is int) {
        return PaymentRedirectScreen(
          bookingId: extra,
          checkoutUrl: null,
          onRetryCheckout: (id) => bookings.retryCheckout(id),
        );
      }
      throw StateError('invalid payment-redirect extra: $extra');
    },
  );
}

GoRoute paymentProofRoute(AppSupabase db) {
  final bookings = SupabaseBookingRepository(db);
  return GoRoute(
    path: '/payment-proof',
    name: AppRoutes.paymentProof,
    builder: (context, state) {
      final extra = state.extra;
      int bookingId = 0;
      int amount = 0;
      if (extra is Map) {
        bookingId = (extra['bookingId'] ?? extra['booking_id'] ?? 0) as int;
        amount = (extra['amount'] ?? extra['paid_amount'] ?? 0) as int;
      } else if (extra is int) {
        bookingId = extra;
      }
      return PaymentProofScreen(
        bookingId: bookingId,
        amount: amount,
        repository: bookings,
      );
    },
  );
}

GoRouter buildRouter({
  required AppSupabase db,
  AuthGateway? authGateway,
  bool Function()? isUserLoggedIn,
}) => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => BottomNavScaffold(
        portalRepository: PortalRepository(db),
        bookingRepository: SupabaseBookingRepository(db),
        complaintsRepository: SupabaseComplaintsRepository(db),
      ),
    ),
    paymentRedirectRoute(db),
    paymentProofRoute(db),
  ],
);

final appRouter = buildRouter(
  db: SupabaseAppSupabase(Supabase.instance.client),
);
