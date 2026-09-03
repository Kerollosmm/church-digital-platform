import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/core/result.dart';
import 'package:admin/features/bookings/event_booking_admin_models.dart';
import 'package:admin/features/bookings/event_bookings_admin_repository.dart';
import 'package:admin/features/cashier/admin_cashier_screen.dart';

class FakeCashierAdminRepository implements EventBookingsAdminRepository {
  List<EventBookingAdminItem> bookings = [
    EventBookingAdminItem(
      id: 'b-101',
      customerId: 'user-1',
      customerName: 'كيرلس مينا',
      customerPhone: '01223344556',
      eventTypeId: 'event-1',
      eventTypeName: 'سر المعمودية المقدس',
      category: 'SACRAMENT',
      startTime: DateTime(2026, 9, 10, 10, 0),
      endTime: DateTime(2026, 9, 10, 11, 30),
      status: 'CONFIRMED',
      totalPricePiastres: 20000,
      paidAmountPiastres: 5000,
    ),
    EventBookingAdminItem(
      id: 'b-102',
      customerId: 'user-2',
      customerName: 'مريم بولس',
      customerPhone: '01099887766',
      eventTypeId: 'event-2',
      eventTypeName: 'رحلة الفيوم',
      category: 'ACTIVITY',
      startTime: DateTime(2026, 9, 15, 7, 0),
      endTime: DateTime(2026, 9, 15, 21, 0),
      status: 'CONFIRMED',
      totalPricePiastres: 30000,
      paidAmountPiastres: 30000,
    ),
  ];

  bool quickCashCalled = false;
  String? lastCollectedBookingId;
  int? lastCollectedAmountPiastres;

  @override
  Future<Either<Failure, List<EventBookingAdminItem>>> fetchEventBookings({
    String? statusFilter,
    String? searchQuery,
    String? categoryFilter,
  }) async {
    var list = bookings;
    if (categoryFilter != null && categoryFilter.isNotEmpty) {
      list = list.where((b) => b.category == categoryFilter).toList();
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      list = list.where((b) {
        final phone = b.customerPhone?.toLowerCase() ?? '';
        final name = b.customerName?.toLowerCase() ?? '';
        return phone.contains(q) || name.contains(q);
      }).toList();
    }
    return Right(list);
  }

  @override
  Future<Either<Failure, List<EventBookingAdminItem>>> searchCashierBookings({
    String? searchQuery,
    String? categoryFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    return fetchEventBookings(
      searchQuery: searchQuery,
      categoryFilter: categoryFilter,
    );
  }

  @override
  Future<Either<Failure, void>> quickCashCollect({
    required String bookingId,
    required int amountPiastres,
    String? collectorNote,
  }) async {
    quickCashCalled = true;
    lastCollectedBookingId = bookingId;
    lastCollectedAmountPiastres = amountPiastres;
    // Optimistic update for test
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      final old = bookings[idx];
      bookings[idx] = EventBookingAdminItem(
        id: old.id,
        customerId: old.customerId,
        customerName: old.customerName,
        customerPhone: old.customerPhone,
        eventTypeId: old.eventTypeId,
        eventTypeName: old.eventTypeName,
        category: old.category,
        startTime: old.startTime,
        endTime: old.endTime,
        status: 'PAID',
        totalPricePiastres: old.totalPricePiastres,
        paidAmountPiastres: old.paidAmountPiastres + amountPiastres,
      );
    }
    return const Right(null);
  }

  @override
  Future<Either<Failure, List<VenueResourceItem>>> fetchVenues() async =>
      const Right([]);

  @override
  Future<Either<Failure, List<PriestAdminItem>>> fetchPriests() async =>
      const Right([]);

  @override
  Future<Either<Failure, List<PriestAdminItem>>> getAvailablePriests({
    required DateTime startTime,
    required DateTime endTime,
  }) async => const Right([]);

  @override
  Future<Either<Failure, void>> assignPriestAndVenue({
    required String bookingId,
    required String venueId,
    required int priestId,
    String? overrideNotes,
  }) async => const Right(null);

  @override
  Future<Either<Failure, List<PriestScheduleItem>>> fetchPriestSchedules({
    DateTime? from,
    DateTime? to,
  }) async => const Right([]);

  @override
  Future<Either<Failure, void>> confirmBooking({
    required String bookingId,
    required String venueId,
    DateTime? confirmedStart,
    DateTime? confirmedEnd,
    String? adminNote,
  }) async => const Right(null);

  @override
  Future<Either<Failure, void>> rejectBooking({
    required String bookingId,
    required String rejectionReason,
  }) async => const Right(null);

  @override
  Future<Either<Failure, void>> recordCashPayment({
    required String bookingId,
    required int amountPiastres,
    String? collectorNote,
  }) async => const Right(null);
}

void main() {
  testWidgets(
    'AdminCashierScreen searches by phone, filters by category, and executes 1-click cash collect',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeRepo = FakeCashierAdminRepository();


      await tester.pumpWidget(
        MaterialApp(home: AdminCashierScreen(repository: fakeRepo)),
      );

      await tester.pumpAndSettle();

      // Verify header and initial list
      expect(find.text('خزينة التحصيل الكنسي المباشر 💵'), findsOneWidget);
      expect(find.text('سر المعمودية المقدس'), findsOneWidget);
      expect(find.text('رحلة الفيوم'), findsOneWidget);
      expect(find.text('المتبقي: 150 ج.م'), findsOneWidget); // 200 - 50 = 150
      expect(find.text('المتبقي: 0 ج.م'), findsOneWidget); // 300 - 300 = 0

      // Search by phone '01223344556'
      await tester.enterText(
        find.byType(TextField).first,
        '01223344556',
      );
      await tester.pumpAndSettle();

      expect(find.text('سر المعمودية المقدس'), findsOneWidget);
      expect(find.text('رحلة الفيوم'), findsNothing);

      // Clear search
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();

      // Filter by Activities
      await tester.tap(find.text('🚌 رحلات ومؤتمرات'));
      await tester.pumpAndSettle();

      expect(find.text('سر المعمودية المقدس'), findsNothing);
      expect(find.text('رحلة الفيوم'), findsOneWidget);

      // Switch back to all
      await tester.tap(find.text('جميع المعاملات'));
      await tester.pumpAndSettle();

      // Tap Cash collect on baptism booking
      await tester.tap(find.text('تحصيل نقدية').first);
      await tester.pumpAndSettle();

      // Verify modal
      expect(find.text('تحصيل سريع: سر المعمودية المقدس'), findsOneWidget);
      expect(find.text('صاحب الحجز: كيرلس مينا'), findsOneWidget);

      expect(find.text('المتبقي للتحصيل:'), findsOneWidget);
      expect(find.text('150.0 ج.م'), findsOneWidget);

      // Confirm cash collection
      await tester.tap(find.text('تأكيد التحصيل وإصدار إشعار'));
      await tester.pumpAndSettle();

      expect(fakeRepo.quickCashCalled, isTrue);
      expect(fakeRepo.lastCollectedBookingId, equals('b-101'));
      expect(fakeRepo.lastCollectedAmountPiastres, equals(15000));
      expect(find.text('تم تحصيل النقدية وتحديث الحجز بنجاح 🎉'), findsOneWidget);
    },
  );

  test('EventBookingAdminItem.fromJson safely parses flat RPC keys', () {
    final flatRpcJson = {
      'id': 'b-rpc-1',
      'customer_id': 'cust-1',
      'customer_name': 'شنودة جورج',
      'customer_phone': '01122334455',
      'event_type_id': 'evt-1',
      'event_type_name': 'سر مسحة المرضى',
      'category': 'SACRAMENT',
      'venue_name': 'هيكل مارمرقس',
      'assigned_priest_id': 12,
      'priest_name': 'أبونا ميخائيل',
      'start_time': '2026-09-12T10:00:00Z',
      'end_time': '2026-09-12T11:00:00Z',
      'status': 'CONFIRMED',
      'total_price_piastres': 10000,
      'paid_amount_piastres': 5000,
    };

    final item = EventBookingAdminItem.fromJson(flatRpcJson);

    expect(item.id, equals('b-rpc-1'));
    expect(item.customerId, equals('cust-1'));
    expect(item.customerName, equals('شنودة جورج'));
    expect(item.customerPhone, equals('01122334455'));
    expect(item.eventTypeName, equals('سر مسحة المرضى'));
    expect(item.category, equals('SACRAMENT'));
    expect(item.venueName, equals('هيكل مارمرقس'));
    expect(item.assignedPriestId, equals(12));
    expect(item.priestName, equals('أبونا ميخائيل'));
    expect(item.totalPriceEgp, equals(100.0));
    expect(item.paidAmountEgp, equals(50.0));
    expect(item.remainingAmountEgp, equals(50.0));
  });

  test('searchCashierBookings returns filtered bookings correctly', () async {
    final repo = FakeCashierAdminRepository();
    final result = await repo.searchCashierBookings(
      searchQuery: 'كيرلس',
      categoryFilter: 'SACRAMENT',
    );

    expect(result.isRight, isTrue);
    result.fold(
      (f) => fail('should not fail: ${f.message}'),
      (list) {
        expect(list.length, equals(1));
        expect(list.first.customerName, equals('كيرلس مينا'));
        expect(list.first.category, equals('SACRAMENT'));
      },
    );
  });
}


