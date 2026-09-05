import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/auth/auth_gateway.dart';
import 'features/booking/payment_proof_screen.dart';
import 'features/complaints/complaints_repository.dart';
import 'features/family_archive/family_certificates_screen.dart';
import 'features/family_archive/sacramental_repository.dart';
import 'features/portal/portal_repository.dart';
import 'repositories/event_booking_repository.dart';
import 'repositories/supabase_booking_repository.dart';
import 'repositories/supabase_event_booking_repository.dart';
import 'screens/event_booking_screen.dart';
import 'services/app_routes.dart';
import 'services/app_supabase.dart';
import 'widgets/bottom_nav_scaffold.dart';

GoRoute eventBookingRoute([EventBookingRepository? repository]) {
  return GoRoute(
    path: '/event-booking',
    name: AppRoutes.eventBooking,
    builder: (context, state) => EventBookingScreen(
      repository: repository ?? SupabaseEventBookingRepository(),
    ),
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

GoRoute familyArchiveRoute(AppSupabase db) {
  return GoRoute(
    path: '/family-archive',
    name: AppRoutes.familyArchive,
    builder: (context, state) {
      return FamilyCertificatesScreen(
        repository: SupabaseSacramentalRecordsRepository(),
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
        sacramentalRepository: SupabaseSacramentalRecordsRepository(),
      ),
    ),
    paymentProofRoute(db),
    familyArchiveRoute(db),
    eventBookingRoute(),
  ],
);

final appRouter = buildRouter(
  db: SupabaseAppSupabase(Supabase.instance.client),
);
