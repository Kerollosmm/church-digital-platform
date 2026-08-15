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
  group('Deep Booking Intake Seam — reserveAndPay & retryCheckout', () {
    late MockAppSupabase mockSupabase;
    late SupabaseBookingRepository repository;

    setUp(() {
      mockSupabase = MockAppSupabase();
      repository = SupabaseBookingRepository(mockSupabase);
    });

    test(
      '1. Paid slot triggers atomic reservation and creates Paymob checkout session',
      () async {
        mockSupabase.rpcResponse = {
          'id': 101,
          'slot_id': 5,
          'user_id': 'aaaaaaaa-0000-0000-0000-000000000002',
          'status': 'PENDING_PAYMENT',
          'paid_amount': 50,
        };
        mockSupabase.functionResponse = {
          'checkout_url':
              'https://accept.paymob.com/standalone?payment_token=token123',
          'payment_id': 9901,
        };

        final result = await repository.reserveAndPay(
          slotId: 5,
          whatsappOptIn: true,
        );

        expect(result.isRight, isTrue);
        final session = result.rightOrNull!;
        expect(session.booking.id, equals(101));
        expect(session.booking.status, equals('PENDING_PAYMENT'));
        expect(
          session.checkoutUrl,
          equals('https://accept.paymob.com/standalone?payment_token=token123'),
        );
        expect(session.paymentId, equals(9901));
        expect(session.isConfirmed, isFalse);

        expect(mockSupabase.rpcCalls, contains('book_slot'));
        expect(mockSupabase.rpcParams['p_slot_id'], equals(5));
        expect(mockSupabase.rpcParams['p_opt_in'], isTrue);
        expect(mockSupabase.functionCalls, contains('paymob-checkout'));
        expect(mockSupabase.functionBodies['booking_id'], equals(101));
      },
    );

    test(
      '2. Free slot (paid_amount == 0) returns session without dispatching Paymob checkout',
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
        final session = result.rightOrNull!;
        expect(session.booking.id, equals(102));
        expect(session.checkoutUrl, isNull);
        expect(session.paymentId, isNull);
        expect(session.isConfirmed, isTrue);

        expect(mockSupabase.rpcCalls, contains('book_slot'));
        expect(mockSupabase.rpcParams['p_opt_in'], isFalse);
        expect(mockSupabase.functionCalls, isEmpty);
      },
    );

    test(
      '3. RPC failure (slot full / PostgrestException) returns Left(BookingFailure) without checkout',
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
        expect(mockSupabase.functionCalls, isEmpty);
      },
    );

    test(
      '4. Checkout failure after successful reservation returns Left(CheckoutFailure) with booking ID',
      () async {
        mockSupabase.rpcResponse = {
          'id': 103,
          'slot_id': 8,
          'user_id': 'aaaaaaaa-0000-0000-0000-000000000002',
          'status': 'PENDING_PAYMENT',
          'paid_amount': 75,
        };
        mockSupabase.functionError = Exception(
          'Paymob Gateway 502 Bad Gateway',
        );

        final result = await repository.reserveAndPay(
          slotId: 8,
          whatsappOptIn: true,
        );

        expect(result.isLeft, isTrue);
        final failure = result.leftOrNull!;
        expect(failure, isA<CheckoutFailure>());
        expect((failure as CheckoutFailure).bookingId, equals(103));
        expect(failure.message, contains('Paymob Gateway 502'));

        expect(mockSupabase.rpcCalls, contains('book_slot'));
        expect(mockSupabase.functionCalls, contains('paymob-checkout'));
      },
    );

    test(
      '5. Paid reservation + empty/missing checkout_url in payload => Left(CheckoutFailure) with bookingId',
      () async {
        mockSupabase.rpcResponse = {
          'id': 104,
          'slot_id': 9,
          'user_id': 'aaaaaaaa-0000-0000-0000-000000000002',
          'status': 'PENDING_PAYMENT',
          'paid_amount': 100,
        };
        // Paymob returns 200 with empty body / missing checkout_url
        mockSupabase.functionResponse = {};

        final result = await repository.reserveAndPay(
          slotId: 9,
          whatsappOptIn: false,
        );

        expect(result.isLeft, isTrue);
        final failure = result.leftOrNull!;
        expect(failure, isA<CheckoutFailure>());
        expect((failure as CheckoutFailure).bookingId, equals(104));
        expect(failure.message, contains('Missing checkout URL'));
      },
    );

    test(
      '6. retryCheckout returns Either<Failure, BookingCheckoutSession> on success and failure',
      () async {
        // Success case: booking exists with PENDING_PAYMENT
        mockSupabase.queryResponse = [
          {
            'id': 201,
            'status': 'PENDING_PAYMENT',
            'paid_amount': 50,
            'title_ar': 'رحلة',
          },
        ];
        mockSupabase.functionResponse = {
          'checkout_url':
              'https://accept.paymob.com/standalone?payment_token=token456',
          'payment_id': 9902,
        };

        final okResult = await repository.retryCheckout(201);
        expect(okResult.isRight, isTrue);
        final session = okResult.rightOrNull!;
        expect(session.booking.id, equals(201));
        expect(session.booking.status, equals('PENDING_PAYMENT'));
        expect(
          session.checkoutUrl,
          equals('https://accept.paymob.com/standalone?payment_token=token456'),
        );
        expect(mockSupabase.queryTables, contains('v_my_bookings'));

        // Error case: Paymob failure
        mockSupabase.queryResponse = [
          {'id': 202, 'status': 'PENDING_PAYMENT', 'paid_amount': 50},
        ];
        mockSupabase.functionError = Exception('Network Timeout');
        final errResult = await repository.retryCheckout(202);
        expect(errResult.isLeft, isTrue);
        final failure = errResult.leftOrNull!;
        expect(failure, isA<CheckoutFailure>());
        expect((failure as CheckoutFailure).bookingId, equals(202));
      },
    );

    test(
      '6b. retryCheckout on non-existent booking returns Left(BookingFailure) without calling paymob-checkout',
      () async {
        mockSupabase.queryResponse = []; // Not found

        final result = await repository.retryCheckout(203);
        expect(result.isLeft, isTrue);
        final failure = result.leftOrNull!;
        expect(failure, isA<BookingFailure>());
        expect(mockSupabase.functionCalls, isNot(contains('paymob-checkout')));
      },
    );

    test(
      '6c. retryCheckout on non-PENDING_PAYMENT booking returns Left(CheckoutFailure) without calling paymob-checkout',
      () async {
        mockSupabase.queryResponse = [
          {'id': 204, 'status': 'CONFIRMED', 'paid_amount': 50},
        ];

        final result = await repository.retryCheckout(204);
        expect(result.isLeft, isTrue);
        final failure = result.leftOrNull!;
        expect(failure, isA<CheckoutFailure>());
        expect(mockSupabase.functionCalls, isNot(contains('paymob-checkout')));
      },
    );

    test('7. Unauthenticated call returns Left(AuthFailure)', () async {
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
      '8. BookingFlowController drives reserveAndPay and provides localized Arabic error messages',
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
      '9. EmptyBookingRepository provides safe no-op implementations without throwing',
      () async {
        final empty = EmptyBookingRepository();
        expect((await empty.reserveAndPay(slotId: 1)).isLeft, isTrue);
        expect((await empty.retryCheckout(1)).isLeft, isTrue);
        await expectLater(empty.cancelBooking(1), completes);
        await expectLater(empty.confirmBooking(1), completes);
        await expectLater(empty.completeBooking(1), completes);
      },
    );

    test(
      '10. Fake adapter reserveAndPay and retryCheckout are slot-aware and deterministic',
      () async {
        final fake = FakeBookingRepository(
          slots: [
            {'id': 12, 'title_ar': 'قداس الأحد', 'price': 0},
            {'id': 13, 'title_ar': 'رحلة دير الأنبا بولا', 'price': 150},
          ],
          checkoutUrl: 'https://accept.paymob.com/checkout?token=abc',
        );

        // Slot 12 is free
        final resFree = await fake.reserveAndPay(slotId: 12);
        expect(resFree.isRight, isTrue);
        expect(resFree.rightOrNull!.booking.id, equals(12));
        expect(resFree.rightOrNull!.isConfirmed, isTrue);
        expect(resFree.rightOrNull!.checkoutUrl, isNull);

        // Slot 13 is paid
        final resPaid = await fake.reserveAndPay(slotId: 13);
        expect(resPaid.isRight, isTrue);
        expect(resPaid.rightOrNull!.booking.id, equals(13));
        expect(resPaid.rightOrNull!.isConfirmed, isFalse);
        expect(
          resPaid.rightOrNull!.checkoutUrl,
          equals('https://accept.paymob.com/checkout?token=abc'),
        );

        // retryCheckout on fake
        final resRetry = await fake.retryCheckout(13);
        expect(resRetry.isRight, isTrue);
        expect(
          resRetry.rightOrNull!.checkoutUrl,
          equals('https://accept.paymob.com/checkout?token=abc'),
        );
      },
    );
  });
}
