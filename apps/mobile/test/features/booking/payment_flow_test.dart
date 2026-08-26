import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/booking/my_bookings_screen.dart';
import 'package:mobile/features/booking/payment_proof_screen.dart';
import 'package:mobile/models/booking_status.dart';
import 'package:mobile/models/resolved_booking_status.dart';
import 'package:mobile/repositories/supabase_booking_repository.dart';
import '../../helpers/pump_with_router.dart';
import '../../helpers/test_app_supabase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async => true,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        );
  });

  test('BookingStatus maps db strings and resolver renders Arabic labels', () {
    expect(
      BookingStatus.fromDb('PENDING_PAYMENT'),
      BookingStatus.pendingPayment,
    );
    expect(
      resolveBookingStatus(BookingStatus.pendingPayment).label,
      'في انتظار الدفع',
    );
  });

  testWidgets(
    'my bookings shows chips and retry button navigates to PaymentProofScreen',
    (tester) async {
      final fake = TestAppSupabase({
        'bookings': [
          {
            'id': 7,
            'slot_id': 1,
            'status': 'PENDING_PAYMENT',
            'paid_amount': 150,
            'created_at': '2026-08-09T08:00:00+02:00',
          },
        ],
        'payout_channels': [
          {
            'id': 1,
            'channel': 'VODAFONE_CASH',
            'display_name_ar': 'فودافون كاش',
            'account_number': '01000000000',
            'holder_name': 'الكنيسة القبطية',
            'is_active': true,
          },
        ],
      });
      final repo = SupabaseBookingRepository(fake);
      await pumpWithRouter(
        tester,
        home: MyBookingsScreen(repository: repo),
        db: fake,
      );
      expect(find.text('في انتظار الدفع'), findsOneWidget);
      await tester.tap(find.text('إعادة الدفع'));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentProofScreen), findsOneWidget);
    },
  );
}
