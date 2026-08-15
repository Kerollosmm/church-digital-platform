import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/booking/my_bookings_screen.dart';
import 'package:mobile/features/booking/payment_redirect_screen.dart';
import 'package:mobile/models/booking_status.dart';
import 'package:mobile/models/resolved_booking_status.dart';
import 'package:mobile/repositories/supabase_booking_repository.dart';
import 'package:mobile/services/app_strings.dart';
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
    'my bookings shows chips and retry button calls checkout for same booking',
    (tester) async {
      final fake = TestAppSupabase(
        {
          'bookings': [
            {
              'id': 7,
              'slot_id': 1,
              'status': 'PENDING_PAYMENT',
              'paid_amount': 0,
              'created_at': '2026-08-09T08:00:00+02:00',
            },
          ],
        },
        rpcHandler: {
          'paymob-checkout': (params) async => {
            'id': 'pay-1',
            'checkout_url': 'https://example.test',
          },
        },
      );
      final repo = SupabaseBookingRepository(fake);
      await pumpWithRouter(
        tester,
        home: MyBookingsScreen(repository: repo),
        db: fake,
      );
      expect(find.text('في انتظار الدفع'), findsOneWidget);
      await tester.tap(find.text('إعادة الدفع'));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentRedirectScreen), findsOneWidget);
      final payBtn = find.text(AppStrings.payNow);
      await tester.ensureVisible(payBtn);
      await tester.tap(payBtn);
      await tester.pumpAndSettle();
      expect(fake.rpcCalls, ['paymob-checkout']);
      expect(fake.rpcArgs['paymob-checkout'], {'booking_id': 7});
    },
  );
}
