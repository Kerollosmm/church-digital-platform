import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/booking/my_bookings_screen.dart';
import 'package:mobile/features/booking/services_list_screen.dart';
import 'package:mobile/features/complaints/complaints_screen.dart';
import 'package:mobile/features/portal/portal_repository.dart';
import 'package:mobile/features/video/video_purchase_screen.dart';
import 'package:mobile/screens/home_hub_screen.dart';
import 'package:mobile/services/app_strings.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/widgets/bottom_nav_scaffold.dart';
import '../helpers/fake_supabase.dart';
import '../helpers/fakes.dart';

void main() {
  testWidgets('BottomNavScaffold renders TopBar and switches tabs on tap', (
    tester,
  ) async {
    final emptyFake = FakeSupabase({'announcements': []});
    final bookingRepo = FakeBookingRepository();
    final videosRepo = FakeVideosRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: BottomNavScaffold(
          homeTab: HomeHubScreen(repository: PortalRepository(emptyFake)),
          bookingRepository: bookingRepo,
          videosRepository: videosRepo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // TopBar title assertion
    expect(find.text(AppStrings.appTitle), findsOneWidget);

    // Initial tab (Home) active assertion
    expect(find.text(AppStrings.quickServicesTitle), findsOneWidget);

    // Active tab has gold pill
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color ==
                AppColors.secondaryContainer,
      ),
      findsWidgets,
    );

    // Tap Tab 1: Booking (ServicesListScreen)
    await tester.tap(find.text(AppStrings.tabBooking));
    await tester.pumpAndSettle();
    expect(find.byType(ServicesListScreen), findsOneWidget);

    // Tap Tab 2: Videos (VideoPurchaseScreen)
    await tester.tap(find.text(AppStrings.tabVideos));
    await tester.pumpAndSettle();
    expect(find.byType(VideoPurchaseScreen), findsOneWidget);

    // Tap Tab 3: Complaints (ComplaintsScreen)
    await tester.tap(find.text(AppStrings.tabComplaints));
    await tester.pumpAndSettle();
    expect(find.byType(ComplaintsScreen), findsOneWidget);

    // Tap Tab 4: MyBookings (MyBookingsScreen)
    await tester.tap(find.text(AppStrings.tabProfile));
    await tester.pumpAndSettle();
    expect(find.byType(MyBookingsScreen), findsOneWidget);

    // Tap Tab 0: Home
    await tester.tap(find.text(AppStrings.tabHome));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.quickServicesTitle), findsOneWidget);
  });
}
