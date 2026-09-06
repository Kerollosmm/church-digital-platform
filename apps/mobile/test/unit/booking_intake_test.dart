import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile/controllers/booking_flow_controller.dart';
import 'package:mobile/core/failure.dart';
import 'package:mobile/repositories/supabase_booking_repository.dart';
import 'package:mobile/services/app_strings.dart';
import 'package:mobile/services/app_supabase.dart';
import '../helpers/fakes.dart';

class MockAppSupabase implements AppSupabase {
  final List<String> rpcCalls = [];
  final Map<String, dynamic> rpcParams = {};
  final List<String> functionCalls = [];
  final Map<String, dynamic> functionBodies = {};

  dynamic rpcResponse;
  Object? rpcError;
  Map<String, dynamic>? functionResponse;
  Object? functionError;

  @override
  Future<dynamic> rpc(
    String functionName, [
    Map<String, dynamic>? params,
  ]) async {
    rpcCalls.add(functionName);
    if (params != null) {
      rpcParams.addAll(params);
    }
    if (rpcError != null) {
      throw rpcError!;
    }
    return rpcResponse;
  }

  @override
  Future<Map<String, dynamic>> invokeFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    functionCalls.add(functionName);
    if (body != null) {
      functionBodies.addAll(body);
    }
    if (functionError != null) {
      throw functionError!;
    }
    return functionResponse ?? {};
  }

  List<Map<String, dynamic>> queryResponse = [];
  final List<String> queryTables = [];
  final Map<String, dynamic> queryFilters = {};

  @override
  Future<List<Map<String, dynamic>>> query(
    String table, {
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
  }) async {
    queryTables.add(table);
    if (filters != null) {
      queryFilters.addAll(filters);
    }
    return queryResponse;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Deep Booking Intake Seam — reserveAndPay', () {
    late MockAppSupabase mockSupabase;
    late SupabaseBookingRepository repository;

    setUp(() {
      mockSupabase = MockAppSupabase();
      repository = SupabaseBookingRepository(mockSupabase);
    });

    test(
      '1. Paid slot triggers atomic reservation and returns Booking in PENDING_PAYMENT',
      () async {
        mockSupabase.rpcResponse = {
          'id': 101,
          'slot_id': 5,
          'user_id': 'aaaaaaaa-0000-0000-0000-000000000002',
          'status': 'PENDING_PAYMENT',
          'paid_amount': 50,
        };

        final result = await repository.reserveAndPay(
          slotId: 5,
          whatsappOptIn: true,
        );

        expect(result.isRight, isTrue);
        final booking = result.rightOrNull!;
        expect(booking.id, equals(101));
        expect(booking.status, equals('PENDING_PAYMENT'));
        expect(booking.paidAmount, equals(50));

        expect(mockSupabase.rpcCalls, contains('book_slot'));
        expect(mockSupabase.rpcParams['p_slot_id'], equals(5));
        expect(mockSupabase.rpcParams['p_opt_in'], isTrue);
      },
    );

    test(
      '2. Free slot (paid_amount == 0) returns booking without payment required',
      () async {
        mockSupabase.rpcResponse = {
          'id': 102,
          'slot_id': 6,
          'user_id': 'aaaaaaaa-0000-0000-0000-000000000002',
          'status': 'PENDING_PAYMENT',
          'paid_amount': 0,
        };

        final result = await repository.reserveAndPay(
          slotId: 6,
          whatsappOptIn: false,
        );

        expect(result.isRight, isTrue);
        final booking = result.rightOrNull!;
        expect(booking.id, equals(102));
        expect(booking.paidAmount, equals(0));

        expect(mockSupabase.rpcCalls, contains('book_slot'));
        expect(mockSupabase.rpcParams['p_opt_in'], isFalse);
      },
    );

    test(
      '3. RPC failure (slot full / PostgrestException) returns Left(BookingFailure)',
      () async {
        mockSupabase.rpcError = const PostgrestException(
          message: 'SLOT_FULL',
          code: 'P0001',
        );

        final result = await repository.reserveAndPay(
          slotId: 7,
          whatsappOptIn: false,
        );

        expect(result.isLeft, isTrue);
        final failure = result.leftOrNull!;
        expect(failure, isA<BookingFailure>());
        expect(failure.message, contains('SLOT_FULL'));
        expect(failure.code, equals('P0001'));

        expect(mockSupabase.rpcCalls, contains('book_slot'));
      },
    );

    test('4. Unauthenticated call returns Left(AuthFailure)', () async {
      mockSupabase.rpcError = const PostgrestException(
        message: 'AUTH_REQUIRED',
        code: '28000',
      );

      final result = await repository.reserveAndPay(
        slotId: 10,
        whatsappOptIn: false,
      );

      expect(result.isLeft, isTrue);
      final failure = result.leftOrNull!;
      expect(failure, isA<AuthFailure>());
      expect(failure.code, equals('28000'));
    });

    test(
      '5. BookingFlowController drives reserveAndPay and provides localized Arabic error messages',
      () async {
        final controller = BookingFlowController(repository);
        mockSupabase.rpcError = const PostgrestException(
          message: 'SLOT_FULL',
          code: 'P0001',
        );

        final result = await controller.reserveAndPay(slotId: 11);
        expect(result.isLeft, isTrue);
        final failure = result.leftOrNull!;
        final localized = controller.localizedMessage(failure);
        expect(localized, equals(AppStrings.slotFull));
      },
    );

    test(
      '6. EmptyBookingRepository provides safe no-op implementations without throwing',
      () async {
        final empty = EmptyBookingRepository();
        expect((await empty.reserveAndPay(slotId: 1)).isLeft, isTrue);
        await expectLater(empty.cancelBooking(1), completes);
        await expectLater(empty.confirmBooking(1), completes);
        await expectLater(empty.completeBooking(1), completes);
      },
    );

    test(
      '7. Fake adapter reserveAndPay is slot-aware and deterministic',
      () async {
        final fake = FakeBookingRepository(
          slots: [
            {'id': 12, 'title_ar': 'قداس الأحد', 'price': 0},
            {'id': 13, 'title_ar': 'رحلة دير الأنبا بولا', 'price': 150},
          ],
        );

        // Slot 12 is free
        final resFree = await fake.reserveAndPay(slotId: 12);
        expect(resFree.isRight, isTrue);
        expect(resFree.rightOrNull!.id, equals(12));
        expect(resFree.rightOrNull!.paidAmount, equals(0));

        // Slot 13 is paid
        final resPaid = await fake.reserveAndPay(slotId: 13);
        expect(resPaid.isRight, isTrue);
        expect(resPaid.rightOrNull!.id, equals(13));
        expect(resPaid.rightOrNull!.paidAmount, equals(50));
      },
    );
  });
}
