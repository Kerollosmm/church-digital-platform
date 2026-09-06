import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/booking/booking_detail_screen.dart';
import 'package:mobile/features/booking/slot_grid_screen.dart';
import 'package:mobile/services/app_strings.dart';
import '../../helpers/fakes.dart';

void main() {
  testWidgets(
    'SlotGridScreen renders slot cards with AVAILABLE, BOOKED, CLOSED status chips and only allows tapping AVAILABLE',
    (tester) async {
      final repo = FakeBookingRepository(
        slots: [
          {
            'slot_id': 101,
            'service_id': 1,
            'title_ar': 'القداس الأول',
            'starts_at': '2026-08-15T06:00:00+02:00',
            'available_seats': 12,
            'slot_status': 'AVAILABLE',
            'location': 'القاعة الرئيسية',
          },
          {
            'slot_id': 102,
            'service_id': 1,
            'title_ar': 'القداس الثاني',
            'starts_at': '2026-08-15T08:30:00+02:00',
            'available_seats': 0,
            'slot_status': 'BOOKED',
          },
          {
            'slot_id': 103,
            'service_id': 1,
            'title_ar': 'قداس خاص',
            'starts_at': '2026-08-15T11:00:00+02:00',
            'available_seats': 0,
            'slot_status': 'CLOSED',
          },
        ],
      );

      await tester.pumpWidget(
        MaterialApp(home: SlotGridScreen(serviceId: 1, repository: repo)),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.selectSlot), findsOneWidget);
      expect(find.text('القداس الأول'), findsOneWidget);
      expect(find.text('القداس الثاني'), findsOneWidget);
      expect(find.text('قداس خاص'), findsOneWidget);

      expect(find.text(AppStrings.statusAvailable), findsWidgets);
      expect(find.text(AppStrings.statusBooked), findsWidgets);
      expect(find.text(AppStrings.statusClosed), findsWidgets);

      // Tapping BOOKED slot does not navigate
      await tester.tap(find.text('القداس الثاني'));
      await tester.pumpAndSettle();
      expect(find.byType(BookingDetailScreen), findsNothing);

      // Tapping CLOSED slot does not navigate
      await tester.tap(find.text('قداس خاص'));
      await tester.pumpAndSettle();
      expect(find.byType(BookingDetailScreen), findsNothing);

      // Tapping AVAILABLE slot navigates to BookingDetailScreen
      await tester.tap(find.text('القداس الأول'));
      await tester.pumpAndSettle();
      expect(find.byType(BookingDetailScreen), findsOneWidget);
    },
  );
}
