import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/core/result.dart';
import 'package:admin/features/allocation/allocation_matrix_screen.dart';
import 'package:admin/features/allocation/assign_priest_venue_dialog.dart';
import 'package:admin/features/bookings/event_booking_admin_models.dart';
import 'package:admin/features/bookings/event_bookings_admin_repository.dart';

class MockAllocationAdminRepository implements EventBookingsAdminRepository {
  List<EventBookingAdminItem> bookings = [
    EventBookingAdminItem(
      id: 'b-101',
      customerId: 'user-101',
      customerName: 'مينا كمال',
      customerPhone: '+201099990001',
      eventTypeId: 'type-1',
      eventTypeName: 'معمودية مباركة',
      assignedVenueId: 'v-1',
      venueName: 'المعمودية الكبرى',
      assignedPriestId: 101,
      priestName: 'أبونا مرقس',
      startTime: DateTime(2026, 9, 10, 10, 0),
      endTime: DateTime(2026, 9, 10, 12, 0),
      status: 'CONFIRMED',
      totalPricePiastres: 25000,
    ),
    EventBookingAdminItem(
      id: 'b-102',
      customerId: 'user-102',
      customerName: 'فادي سمير',
      customerPhone: '+201099990002',
      eventTypeId: 'type-2',
      eventTypeName: 'إكليل مقدس',
      startTime: DateTime(2026, 9, 10, 18, 0),
      endTime: DateTime(2026, 9, 10, 20, 0),
      status: 'SUBMITTED',
      totalPricePiastres: 50000,
    ),
  ];

  List<VenueResourceItem> venues = [
    const VenueResourceItem(
      id: 'v-1',
      nameAr: 'المعمودية الكبرى',
      locationDetailsAr: 'الدور الأرضي',
    ),
    const VenueResourceItem(
      id: 'v-2',
      nameAr: 'القاعة الرئيسية',
      locationDetailsAr: 'الدور الأول',
    ),
  ];

  List<PriestAdminItem> priests = [
    const PriestAdminItem(
      id: 101,
      name: 'أبونا مرقس',
      phone: '+201011111111',
      rank: 'HEGUMEN',
    ),
    const PriestAdminItem(
      id: 102,
      name: 'أبونا يوحنا',
      phone: '+201022222222',
      rank: 'PRIEST',
    ),
  ];

  bool assignCalled = false;
  String? lastAssignedBookingId;
  String? lastAssignedVenueId;
  int? lastAssignedPriestId;

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
  Future<Either<Failure, List<PriestAdminItem>>> fetchPriests() async {
    return Right(priests);
  }

  @override
  Future<Either<Failure, List<PriestAdminItem>>> getAvailablePriests({
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    return Right(priests);
  }

  @override
  Future<Either<Failure, void>> assignPriestAndVenue({
    required String bookingId,
    required String venueId,
    required int priestId,
    String? overrideNotes,
  }) async {
    assignCalled = true;
    lastAssignedBookingId = bookingId;
    lastAssignedVenueId = venueId;
    lastAssignedPriestId = priestId;
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
  Future<Either<Failure, void>> confirmBooking({
    required String bookingId,
    required String venueId,
    DateTime? confirmedStart,
    DateTime? confirmedEnd,
    String? adminNote,
  }) async {
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> rejectBooking({
    required String bookingId,
    required String rejectionReason,
  }) async {
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> recordCashPayment({
    required String bookingId,
    required int amountPiastres,
    String? collectorNote,
  }) async {
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> quickCashCollect({
    required String bookingId,
    required int amountPiastres,
    String? collectorNote,
  }) async {
    return const Right(null);
  }
}


void main() {
  group('AllocationMatrixCalendarScreen & AssignPriestVenueDialog', () {
    testWidgets('renders matrix grid and unassigned queue', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockRepo = MockAllocationAdminRepository();

      await tester.pumpWidget(
        MaterialApp(home: AllocationMatrixCalendarScreen(repository: mockRepo)),
      );

      await tester.pumpAndSettle();

      // Matrix header & venues
      expect(find.text('مصفوفة تخصيص القاعات والآباء الكهنة'), findsOneWidget);
      expect(find.text('المعمودية الكبرى'), findsWidgets);
      expect(find.text('القاعة الرئيسية'), findsWidgets);

      // Unassigned queue sidebar
      expect(find.text('طلبات بانتظار التخصيص (1)'), findsOneWidget);
      expect(find.text('إكليل مقدس'), findsOneWidget);
      expect(find.text('إسناد وتأكيد'), findsOneWidget);
    });

    testWidgets('AssignPriestVenueDialog loads available priests and assigns', (
      tester,
    ) async {
      final mockRepo = MockAllocationAdminRepository();
      final unassignedBooking = mockRepo.bookings[1];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssignPriestVenueDialog(
              booking: unassignedBooking,
              venues: mockRepo.venues,
              repository: mockRepo,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.text('إسناد القاعة والأب الكاهن - إكليل مقدس'),
        findsOneWidget,
      );

      // Tap confirm button
      await tester.tap(find.text('تأكيد وإسناد'));
      await tester.pumpAndSettle();

      expect(mockRepo.assignCalled, isTrue);
      expect(mockRepo.lastAssignedBookingId, equals('b-102'));
      expect(mockRepo.lastAssignedVenueId, equals('v-1'));
      expect(mockRepo.lastAssignedPriestId, equals(101));
    });
  });
}
