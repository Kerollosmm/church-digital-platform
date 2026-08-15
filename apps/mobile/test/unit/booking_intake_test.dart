import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile/core/either.dart';
import 'package:mobile/core/failure.dart';
import 'package:mobile/models/booking.dart';
import 'package:mobile/models/booking_checkout_session.dart';
import 'package:mobile/repositories/booking_repository.dart';
import 'package:mobile/repositories/supabase_booking_repository.dart';
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
  Future<dynamic> rpc(String functionName, [Map<String, dynamic>? params]) async {
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
  Future<Map<String, dynamic>> invokeFunction(String functionName, {Map<String, dynamic>? body}) async {
    functionCalls.add(functionName);
    if (body != null) {
      functionBodies.addAll(body);
    }
    if (functionError != null) {
      throw functionError!;
    }
    return functionResponse ?? {};
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

    test('1. Paid slot triggers atomic reservation and creates Paymob checkout session', () async {
      mockSupabase.rpcResponse = {
        'id': 101,
        'slot_id': 5,
        'user_id': 'aaaaaaaa-0000-0000-0000-000000000002',
        'status': 'PENDING_PAYMENT',
        'paid_amount': 50,
      };
      mockSupabase.functionResponse = {
        'checkout_url': 'https://accept.paymob.com/standalone?payment_token=token123',
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
      expect(session.checkoutUrl, equals('https://accept.paymob.com/standalone?payment_token=token123'));
      expect(session.paymentId, equals(9901));
      expect(session.isConfirmed, isFalse);

      expect(mockSupabase.rpcCalls, contains('book_slot'));
      expect(mockSupabase.rpcParams['p_slot_id'], equals(5));
      expect(mockSupabase.rpcParams['p_opt_in'], isTrue);
      expect(mockSupabase.functionCalls, contains('paymob-checkout'));
      expect(mockSupabase.functionBodies['booking_id'], equals(101));
    });

    test('2. Free slot (paid_amount == 0) returns session without dispatching Paymob checkout', () async {
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
    });

    test('3. RPC failure (slot full / PostgrestException) returns Left(BookingFailure) without checkout', () async {
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
    });

    test('4. Checkout failure after successful reservation returns Left(CheckoutFailure) with booking ID', () async {
      mockSupabase.rpcResponse = {
        'id': 103,
        'slot_id': 8,
        'user_id': 'aaaaaaaa-0000-0000-0000-000000000002',
        'status': 'PENDING_PAYMENT',
        'paid_amount': 75,
      };
      mockSupabase.functionError = Exception('Paymob Gateway 502 Bad Gateway');

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
    });

    test('5. Unauthenticated call returns Left(AuthFailure)', () async {
      mockSupabase.rpcError = const PostgrestException(
        message: 'AUTH_REQUIRED',
        code: '28000',
      );

      final result = await repository.reserveAndPay(
        slotId: 9,
        whatsappOptIn: false,
      );

      expect(result.isLeft, isTrue);
      final failure = result.leftOrNull!;
      expect(failure, isA<AuthFailure>());
      expect(failure.code, equals('28000'));
    });

    test('6. Fake adapter reserveAndPay is slot-aware and deterministic without network', () async {
      final fake = FakeBookingRepository(
        slots: [
          {'id': 10, 'title_ar': 'قداس الأحد', 'price': 0},
          {'id': 11, 'title_ar': 'رحلة دير الأنبا بولا', 'price': 150},
        ],
        checkoutUrl: 'https://accept.paymob.com/checkout?token=abc',
      );

      // Slot 10 is free
      final resFree = await fake.reserveAndPay(slotId: 10);
      expect(resFree.isRight, isTrue);
      expect(resFree.rightOrNull!.booking.id, equals(10));
      expect(resFree.rightOrNull!.isConfirmed, isTrue);
      expect(resFree.rightOrNull!.checkoutUrl, isNull);

      // Slot 11 is paid
      final resPaid = await fake.reserveAndPay(slotId: 11);
      expect(resPaid.isRight, isTrue);
      expect(resPaid.rightOrNull!.booking.id, equals(11));
      expect(resPaid.rightOrNull!.isConfirmed, isFalse);
      expect(resPaid.rightOrNull!.checkoutUrl, equals('https://accept.paymob.com/checkout?token=abc'));
    });
  });
}
