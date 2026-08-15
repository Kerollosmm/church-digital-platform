import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/auth/auth_gateway.dart';
import 'features/booking/payment_redirect_screen.dart';
import 'features/complaints/complaints_repository.dart';
import 'features/portal/portal_repository.dart';
import 'features/video/video_purchase_screen.dart';
import 'repositories/supabase_booking_repository.dart';
import 'repositories/videos_repository.dart';
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
      if (extra is Map && extra['video'] == true) {
        // Video checkout is out of scope for this pass and still a write leak.
        final paymentId = extra['payment_id'];
        if (paymentId is! int) {
          throw StateError('payment_id missing or not int');
        }
        return PaymentRedirectScreen(
          bookingId: paymentId,
          fetchCheckoutUrl: (_) async {
            final data = await db.invokeFunction(
              'paymob-checkout',
              body: {'payment_id': paymentId},
            );
            final url = data['checkout_url'] as String?;
            if (url == null || url.isEmpty) {
              throw StateError('checkout_url missing');
            }
            return url;
          },
        );
      }
      if (extra is Map) {
        final bookingId = (extra['bookingId'] ?? extra['booking_id']) as int?;
        if (bookingId != null) {
          final checkoutUrl =
              (extra['checkoutUrl'] ?? extra['checkout_url']) as String?;
          return PaymentRedirectScreen(
            bookingId: bookingId,
            checkoutUrl: checkoutUrl,
            onRetryCheckout: (id) => bookings.retryCheckout(id),
          );
        }
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

GoRouter buildRouter({
  required AppSupabase db,
  required VideosRepository videos,
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
        videosRepository: videos,
        complaintsRepository: SupabaseComplaintsRepository(db),
      ),
    ),
    GoRoute(
      path: '/videos',
      name: 'videos',
      builder: (_, _) => VideoPurchaseScreen(repository: videos),
    ),
    paymentRedirectRoute(db),
  ],
);

final appRouter = buildRouter(
  db: SupabaseAppSupabase(Supabase.instance.client),
  videos: SupabaseVideosRepository(Supabase.instance.client),
);
