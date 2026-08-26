import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/either.dart';
import 'package:mobile/core/failure.dart';
import 'package:mobile/models/event_booking.dart';
import 'package:mobile/repositories/event_booking_repository.dart';
import 'package:mobile/screens/event_booking_screen.dart';

class FakeEventBookingRepository implements EventBookingRepository {
  List<EventType> eventTypes = [
    const EventType(
      id: 'type-1',
      nameAr: 'إكليل زواج',
      basePricePiastres: 50000,
      defaultDurationMinutes: 120,
    ),
  ];

  List<ExtraService> extraServices = [
    const ExtraService(
      id: 'extra-1',
      nameAr: 'تصوير فيديو',
      pricePiastres: 10000,
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
    'EventBookingScreen loads event types, toggles extra service, and calculates total',
    (tester) async {
      final fakeRepo = FakeEventBookingRepository();

      await tester.pumpWidget(
        MaterialApp(home: EventBookingScreen(repository: fakeRepo)),
      );

      await tester.pumpAndSettle();

      // Verify event type loaded
      expect(find.text('نوع المناسبة'), findsOneWidget);
      expect(find.text('إكليل زواج (500 ج.م)'), findsOneWidget);
      expect(find.text('500 ج.م'), findsOneWidget);

      // Verify extra service listed
      expect(find.text('تصوير فيديو'), findsOneWidget);

      // Check extra service checkbox
      await tester.tap(find.text('تصوير فيديو'));
      await tester.pumpAndSettle();

      // Total should update: 500 base + 100 extra = 600 EGP
      expect(find.text('600 ج.م'), findsOneWidget);

      // Ensure button is visible before tap in SingleChildScrollView
      final submitButtonFinder = find.text('تأكيد طلب الحجز');
      await tester.ensureVisible(submitButtonFinder);
      await tester.pumpAndSettle();
      await tester.tap(submitButtonFinder);
      await tester.pumpAndSettle();

      expect(fakeRepo.submitCalled, isTrue);
    },
  );
}
