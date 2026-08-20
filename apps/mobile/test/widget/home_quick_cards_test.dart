import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/portal/portal_repository.dart';
import 'package:mobile/screens/home_hub_screen.dart';
import 'package:mobile/services/app_strings.dart';
import 'package:mobile/theme/app_theme.dart';
import '../helpers/fake_supabase.dart';

void main() {
  testWidgets(
    'HomeHubScreen quick cards have onTap handlers that trigger callbacks',
    (tester) async {
      final emptyFake = FakeSupabase({'announcements': []});
      bool massTapped = false;
      bool confessionTapped = false;
      bool bookingTapped = false;
      bool complaintsTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: HomeHubScreen(
              repository: PortalRepository(emptyFake),
              onTapMass: () => massTapped = true,
              onTapConfession: () => confessionTapped = true,
              onTapBooking: () => bookingTapped = true,
              onTapComplaints: () => complaintsTapped = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap quick Mass card
      final massCard = find.text(AppStrings.quickMass);
      await tester.ensureVisible(massCard);
      await tester.tap(massCard);
      await tester.pumpAndSettle();
      expect(massTapped, isTrue);

      // Tap quick Confession card
      final confessionCard = find.text(AppStrings.quickConfession);
      await tester.ensureVisible(confessionCard);
      await tester.tap(confessionCard);
      await tester.pumpAndSettle();
      expect(confessionTapped, isTrue);

      // Tap quick Booking card
      final bookingCard = find.text(AppStrings.quickBooking);
      await tester.ensureVisible(bookingCard);
      await tester.tap(bookingCard);
      await tester.pumpAndSettle();
      expect(bookingTapped, isTrue);

      // Tap quick Complaints card
      final complaintsCard = find.text(AppStrings.quickComplaints);
      await tester.ensureVisible(complaintsCard);
      await tester.tap(complaintsCard);
      await tester.pumpAndSettle();
      expect(complaintsTapped, isTrue);
    },
  );
}
