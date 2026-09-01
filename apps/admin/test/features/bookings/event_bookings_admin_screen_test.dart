import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/core/result.dart';
import 'package:admin/features/bookings/event_booking_admin_models.dart';
import 'package:admin/features/bookings/event_bookings_admin_repository.dart';
import 'package:admin/features/bookings/event_bookings_admin_screen.dart';

class FakeEventBookingsAdminRepository implements EventBookingsAdminRepository {
  List<EventBookingAdminItem> bookings = [
    EventBookingAdminItem(
      id: 'b-1',
      customerId: 'user-1',
      customerName: 'بيتر حنا',
      customerPhone: '+201000000001',
      eventTypeId: 'event-1',
      eventTypeName: 'إكليل زواج',
      startTime: DateTime(2026, 9, 1, 18, 0),
      endTime: DateTime(2026, 9, 1, 20, 0),
      status: 'SUBMITTED',
      totalPricePiastres: 50000,
      paidAmountPiastres: 0,
    ),
  ];

  List<VenueResourceItem> venues = [
    const VenueResourceItem(id: 'venue-1', nameAr: 'القاعة الكبرى'),
  ];

  bool confirmCalled = false;
  bool rejectCalled = false;
  bool cashPaymentCalled = false;

  @override
  Future<Either<Failure, List<EventBookingAdminItem>>> fetchEventBookings({
    String? statusFilter,
    String? searchQuery,
    String? categoryFilter,
  }) async {
    return Right(bookings);
  }

  @override
  Future<Either<Failure, List<VenueResourceItem>>> fetchVenues() async {
    return Right(venues);
  }

  @override
  Future<Either<Failure, void>> confirmBooking({
    required String bookingId,
    required String venueId,
    DateTime? confirmedStart,
    DateTime? confirmedEnd,
    String? adminNote,
  }) async {
    confirmCalled = true;
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> rejectBooking({
    required String bookingId,
    required String rejectionReason,
  }) async {
    rejectCalled = true;
    return const Right(null);
  }

  @override
  Future<Either<Failure, List<PriestAdminItem>>> fetchPriests() async {
    return const Right([]);
  }

  @override
  Future<Either<Failure, List<PriestAdminItem>>> getAvailablePriests({
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    return const Right([]);
  }

  @override
  Future<Either<Failure, void>> assignPriestAndVenue({
    required String bookingId,
    required String venueId,
    required int priestId,
    String? overrideNotes,
  }) async {
    return const Right(null);
  }

  @override
  Future<Either<Failure, List<PriestScheduleItem>>> fetchPriestSchedules({
    DateTime? from,
    DateTime? to,
  }) async {
    return const Right([]);
  }

  @override
  Future<Either<Failure, void>> recordCashPayment({
    required String bookingId,
    required int amountPiastres,
    String? collectorNote,
  }) async {
    cashPaymentCalled = true;
    return const Right(null);
  }

  bool quickCashCalled = false;

  @override
  Future<Either<Failure, void>> quickCashCollect({
    required String bookingId,
    required int amountPiastres,
    String? collectorNote,
  }) async {
    quickCashCalled = true;
    return const Right(null);
  }
}


void main() {
  testWidgets(
    'EventBookingsAdminScreen renders bookings and opens confirmation modal',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeRepo = FakeEventBookingsAdminRepository();


      await tester.pumpWidget(
        MaterialApp(home: EventBookingsAdminScreen(repository: fakeRepo)),
      );

      await tester.pumpAndSettle();

      // Verify booking card displayed
      expect(find.text('إكليل زواج'), findsOneWidget);
      expect(find.text('المطالب: بيتر حنا (+201000000001)'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'SUBMITTED'), findsOneWidget);

      // Tap confirm button
      await tester.tap(find.text('تأكيد وتعيين مكان'));
      await tester.pumpAndSettle();

      // Verify modal dialog opens
      expect(find.text('تأكيد حجز إكليل زواج'), findsOneWidget);
      expect(find.text('القاعة الكبرى'), findsOneWidget);

      // Confirm in dialog
      await tester.tap(find.text('تأكيد وتعيين'));
      await tester.pumpAndSettle();

      expect(fakeRepo.confirmCalled, isTrue);
    },
  );

  testWidgets(
    'EventBookingsAdminScreen filters by track queues (SACRAMENT vs ACTIVITY)',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeRepo = FakeEventBookingsAdminRepository();
      fakeRepo.bookings = [
        EventBookingAdminItem(
          id: 'b-1',
          customerId: 'user-1',
          customerName: 'بيتر حنا',
          customerPhone: '+201000000001',
          eventTypeId: 'event-1',
          eventTypeName: 'إكليل زواج',
          category: 'SACRAMENT',
          requiredDocumentsAr: ['شهادة خلو موانع'],
          startTime: DateTime(2026, 9, 1, 18, 0),
          endTime: DateTime(2026, 9, 1, 20, 0),
          status: 'SUBMITTED',
          totalPricePiastres: 50000,
          paidAmountPiastres: 0,
        ),
        EventBookingAdminItem(
          id: 'b-2',
          customerId: 'user-2',
          customerName: 'مريم جورج',
          customerPhone: '+201000000002',
          eventTypeId: 'event-2',
          eventTypeName: 'رحلة وادي النطرون',
          category: 'ACTIVITY',
          startTime: DateTime(2026, 9, 5, 8, 0),
          endTime: DateTime(2026, 9, 5, 20, 0),
          status: 'CONFIRMED',
          totalPricePiastres: 15000,
          paidAmountPiastres: 0,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(home: EventBookingsAdminScreen(repository: fakeRepo)),
      );

      await tester.pumpAndSettle();

      // Both shown in all
      expect(find.text('إكليل زواج'), findsOneWidget);
      expect(find.text('رحلة وادي النطرون'), findsOneWidget);
      expect(find.text('شهادة خلو موانع'), findsOneWidget);

      // Filter by Sacraments
      await tester.tap(find.text('✝️ طابور الأسرار والمناسبات الكنسية'));
      await tester.pumpAndSettle();

      expect(find.text('إكليل زواج'), findsOneWidget);
      expect(find.text('رحلة وادي النطرون'), findsNothing);

      // Filter by Activities
      await tester.tap(find.text('🚌 طابور الرحلات والمؤتمرات'));
      await tester.pumpAndSettle();

      expect(find.text('إكليل زواج'), findsNothing);
      expect(find.text('رحلة وادي النطرون'), findsOneWidget);
    },
  );
}
