import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/booking/services_list_screen.dart';
import 'package:mobile/features/booking/slot_grid_screen.dart';
import 'package:mobile/services/app_strings.dart';
import '../../helpers/fakes.dart';

void main() {
  testWidgets(
    'ServicesListScreen renders services list with Arabic title and navigates to SlotGridScreen',
    (tester) async {
      final repo = FakeBookingRepository(
        services: [
          {
            'id': 1,
            'title_ar': 'قداس الأحد',
            'price_from': 50,
            'location': 'الكنيسة الكبيرة',
          },
        ],
      );

      await tester.pumpWidget(
        MaterialApp(home: ServicesListScreen(repository: repo)),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.selectSlot), findsOneWidget);
      expect(find.text('قداس الأحد'), findsOneWidget);
      expect(
        find.text('${AppStrings.priceFrom} 50 ${AppStrings.egp}'),
        findsOneWidget,
      );
      expect(find.text('الكنيسة الكبيرة'), findsOneWidget);

      await tester.tap(find.text('قداس الأحد'));
      await tester.pumpAndSettle();

      expect(find.byType(SlotGridScreen), findsOneWidget);
    },
  );
}
