import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:admin/app_router.dart';
import 'package:admin/features/analytics/analytics_admin_screen.dart';
import 'package:admin/features/bookings/manual_book_screen.dart';
import 'package:admin/features/bookings/emergency_override_screen.dart';
import 'package:admin/features/complaints/complaints_admin_screen.dart';
import 'package:admin/features/content/announcements_admin_screen.dart';
import 'package:admin/features/content/faq_admin_screen.dart';
import 'package:admin/features/payments/payments_admin_screen.dart';
import 'package:admin/features/slots/slots_admin_screen.dart';
import '../helpers/mock_supabase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      Supabase.instance;
    } catch (_) {
      await Supabase.initialize(
        url: 'https://qksgphryemrdrkwaqnxp.supabase.co',
        publishableKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFrc2dwaHJ5ZW1yZHJrd2FxbnhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU5NTA2MjgsImV4cCI6MjEwMTUyNjYyOH0.ebxE042EdeYMHbkJnst8aq5K6RtlYgUXEpoeHuYNHvA',
        authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      );
    }
  });

  Widget buildTestApp(SupabaseClient fake) {
    return ProviderScope(
      child: MaterialApp.router(
        routerConfig: createAdminRouter(
          isAuthenticated: () => true,
          getUserRole: () => 'ADMIN',
          db: fake,
        ),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }

  testWidgets('ShellRoute drawer navigation renders all items and navigates correctly', (tester) async {
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final fake = MockSupabase(tables: {
      'bookings': [],
      'service_slots': [],
      'v_complaints': [],
      'announcements': [],
      'faq': [],
      'payments': [],
      'v_available_slots': [],
    }).build();

    await tester.pumpWidget(buildTestApp(fake));
    await tester.pump();

    expect(find.text('الحجوزات'), findsWidgets);
    expect(find.text('المواعيد'), findsOneWidget);
    expect(find.text('حجز يدوي'), findsOneWidget);
    expect(find.text('طوارئ'), findsOneWidget);
    expect(find.text('الشكاوى'), findsOneWidget);
    expect(find.text('الإعلانات'), findsOneWidget);
    expect(find.text('الأسئلة الشائعة'), findsOneWidget);
    expect(find.text('المدفوعات'), findsOneWidget);
    expect(find.text('التحليلات'), findsOneWidget);

    await tester.tap(find.text('حجز يدوي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ManualBookScreen), findsOneWidget);

    await tester.tap(find.text('طوارئ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(EmergencyOverrideScreen), findsOneWidget);

    await tester.tap(find.text('الشكاوى'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ComplaintsAdminScreen), findsOneWidget);

    await tester.tap(find.text('المواعيد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SlotsAdminScreen), findsOneWidget);

    await tester.tap(find.text('الإعلانات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AnnouncementsAdminScreen), findsOneWidget);

    await tester.tap(find.text('الأسئلة الشائعة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(FaqAdminScreen), findsOneWidget);

    await tester.tap(find.text('المدفوعات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PaymentsAdminScreen), findsOneWidget);

    await tester.tap(find.text('التحليلات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AnalyticsAdminScreen), findsOneWidget);
  });
}
