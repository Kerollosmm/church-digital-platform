import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/app_router.dart';
import 'package:mobile/core/either.dart';
import 'package:mobile/core/failure.dart';
import 'package:mobile/models/event_booking.dart';
import 'package:mobile/repositories/event_booking_repository.dart';
import 'package:mobile/screens/event_booking_screen.dart';
import 'package:mobile/services/app_routes.dart';

class FakeEventBookingRepository implements EventBookingRepository {
  List<EventType> eventTypes = [
    const EventType(
      id: 'type-1',
      nameAr: 'إكليل زواج',
      basePricePiastres: 50000,
      defaultDurationMinutes: 120,
      category: 'SACRAMENT',
      requiredDocumentsAr: ['شهادة خلو موانع', 'شهادة دورة المشورة الأسرية'],
    ),
    const EventType(
      id: 'type-2',
      nameAr: 'رحلة دير الأنبا بيشوي',
      basePricePiastres: 15000,
      defaultDurationMinutes: 360,
      category: 'ACTIVITY',
      requiredDocumentsAr: [],
    ),
  ];

  List<ExtraService> extraServices = [
    const ExtraService(
      id: 'extra-1',
      nameAr: 'وجبة غداء إضافية',
      pricePiastres: 5000,
    ),
  ];

  bool submitCalled = false;

  @override
  Future<Either<Failure, List<EventType>>> fetchEventTypes() async {
    return Right(eventTypes);
  }

  @override
  Future<Either<Failure, List<ExtraService>>> fetchExtraServicesForEvent(
    String eventTypeId,
  ) async {
    return Right(extraServices);
  }

  @override
  Future<Either<Failure, String>> submitEventBooking({
    required String eventTypeId,
    required DateTime startTime,
    required List<Map<String, dynamic>> extraServices,
    String? notes,
  }) async {
    submitCalled = true;
    return const Right('booking-123');
  }

  @override
  Future<Either<Failure, List<EventBooking>>> fetchMyEventBookings() async {
    return const Right([]);
  }
}

void main() {
  testWidgets(
    'EventBookingScreen handles SACRAMENT track (shows documents, hides commercial extras)',
    (tester) async {
      final fakeRepo = FakeEventBookingRepository();

      await tester.pumpWidget(
        MaterialApp(home: EventBookingScreen(repository: fakeRepo)),
      );

      await tester.pumpAndSettle();

      // Verify sacrament loaded
      expect(find.text('نوع المناسبة'), findsOneWidget);
      expect(find.text('إكليل زواج (500 ج.م)'), findsOneWidget);

      // Documents card shown
      expect(find.text('الأوراق والمستندات المطلوبة:'), findsOneWidget);
      expect(find.text('شهادة خلو موانع'), findsOneWidget);
      expect(find.text('شهادة دورة المشورة الأسرية'), findsOneWidget);

      // Commercial extra services hidden
      expect(find.text('الخدمات الإضافية'), findsNothing);
      expect(find.text('وجبة غداء إضافية'), findsNothing);

      // Verify pastoral submit button
      final submitButtonFinder = find.text('إرسال طلب الحجز للمراجعة الكنسية');
      await tester.ensureVisible(submitButtonFinder);
      await tester.pumpAndSettle();
      await tester.tap(submitButtonFinder);
      await tester.pumpAndSettle();

      expect(fakeRepo.submitCalled, isTrue);
    },
  );

  testWidgets(
    'EventBookingScreen handles ACTIVITY track (shows extra services and add-ons)',
    (tester) async {
      final fakeRepo = FakeEventBookingRepository();
      // Start with activity selected as first
      fakeRepo.eventTypes = [
        const EventType(
          id: 'type-2',
          nameAr: 'رحلة دير الأنبا بيشوي',
          basePricePiastres: 15000,
          defaultDurationMinutes: 360,
          category: 'ACTIVITY',
          requiredDocumentsAr: [],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(home: EventBookingScreen(repository: fakeRepo)),
      );

      await tester.pumpAndSettle();

      // Verify activity loaded
      expect(find.text('رحلة دير الأنبا بيشوي (150 ج.م)'), findsOneWidget);

      // Documents card hidden
      expect(find.text('الأوراق والمستندات المطلوبة:'), findsNothing);

      // Commercial extras shown
      expect(find.text('الخدمات الإضافية'), findsOneWidget);
      expect(find.text('وجبة غداء إضافية'), findsOneWidget);

      // Select extra
      await tester.tap(find.text('وجبة غداء إضافية'));
      await tester.pumpAndSettle();

      // Total updates: 150 + 50 = 200 EGP
      expect(find.text('200 ج.م'), findsOneWidget);

      // Submit button text
      final submitButtonFinder = find.text('تأكيد طلب الحجز');
      await tester.ensureVisible(submitButtonFinder);
      await tester.pumpAndSettle();
      await tester.tap(submitButtonFinder);
      await tester.pumpAndSettle();

      expect(fakeRepo.submitCalled, isTrue);
    },
  );

  testWidgets('event booking screen is reachable via named route', (tester) async {
    final fakeRepo = FakeEventBookingRepository();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => context.pushNamed(AppRoutes.eventBooking),
              child: const Text('go'),
            ),
          ),
        ),
        eventBookingRoute(fakeRepo),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(EventBookingScreen), findsOneWidget);
  });
}
