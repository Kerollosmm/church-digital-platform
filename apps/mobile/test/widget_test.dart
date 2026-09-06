import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/portal/portal_repository.dart';
import 'package:mobile/screens/home_hub_screen.dart';
import 'package:mobile/services/app_strings.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/widgets/bottom_nav_scaffold.dart';
import 'helpers/fake_supabase.dart';
import 'helpers/fakes.dart';

void main() {
  testWidgets('home smoke renders with mocked supabase client', (tester) async {
    final fake = FakeSupabase({'announcements': []});
    final bookingRepo = FakeBookingRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: BottomNavScaffold(
          homeTab: HomeHubScreen(repository: PortalRepository(fake)),
          bookingRepository: bookingRepo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.appTitle), findsOneWidget);
    expect(find.text(AppStrings.quickServicesTitle), findsOneWidget);
  });
}
