import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/booking/booking_detail_screen.dart';
import 'package:mobile/features/booking/payment_proof_screen.dart';
import 'package:mobile/features/booking/services_list_screen.dart';
import 'package:mobile/features/booking/slot_grid_screen.dart';
import 'package:mobile/repositories/supabase_booking_repository.dart';
import '../../helpers/pump_with_router.dart';
import '../../helpers/test_app_supabase.dart';

void main() {
  testWidgets('service list -> slot grid -> detail -> book_slot with opt-in', (
    tester,
  ) async {
    final fake = TestAppSupabase(
      {
        'v_services': [
          {'id': 1, 'title_ar': 'قداس', 'price_from': 50},
        ],
        'v_available_slots': [
          {
            'slot_id': 11,
            'service_id': 1,
            'title_ar': 'قداس',
            'starts_at': '2026-08-09T08:00:00+02:00',
            'price': 50,
            'slot_status': 'AVAILABLE',
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
      },
      rpcHandler: {
        'book_slot': (params) async => {
          'id': 42,
          'status': 'PENDING_PAYMENT',
          'paid_amount': 50,
        },
      },
    );
    final repo = SupabaseBookingRepository(fake);
    await pumpWithRouter(
      tester,
      home: ServicesListScreen(repository: repo),
      db: fake,
    );
    await tester.tap(find.text('قداس'));
    await tester.pumpAndSettle();
    expect(find.byType(SlotGridScreen), findsOneWidget);
    await tester.tap(find.text('08:00'));
    await tester.pumpAndSettle();
    expect(find.byType(BookingDetailScreen), findsOneWidget);
    await tester.tap(find.text('موافقة على استقبال رسائل واتساب'));
    await tester.tap(find.widgetWithText(FilledButton, 'تأكيد الحجز'));
    await tester.pumpAndSettle();
    expect(fake.rpcCalls, ['book_slot']);
    expect(fake.rpcArgs['book_slot'], {'p_slot_id': 11, 'p_opt_in': true});
    expect(find.byType(PaymentProofScreen), findsOneWidget);
  });
}
