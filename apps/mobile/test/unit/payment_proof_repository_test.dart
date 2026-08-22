import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile/core/failure.dart';
import 'package:mobile/models/payment_channel.dart';
import 'package:mobile/models/payment_proof_input.dart';
import 'package:mobile/models/payout_channel.dart';
import 'package:mobile/repositories/supabase_booking_repository.dart';
import 'package:mobile/services/app_supabase.dart';

class MockAppSupabase implements AppSupabase {
  final List<String> rpcCalls = [];
  final Map<String, dynamic> rpcParams = {};
  final List<String> queryTables = [];
  final List<String> storageCalls = [];

  dynamic rpcResponse;
  Object? rpcError;
  List<Map<String, dynamic>> queryResponse = [];
  Object? queryError;

  @override
  Future<dynamic> rpc(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    rpcCalls.add(functionName);
    rpcParams.addAll(params);
    if (rpcError != null) throw rpcError!;
    return rpcResponse;
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String table, {
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
  }) async {
    queryTables.add(table);
    if (queryError != null) throw queryError!;
    return queryResponse;
  }

  @override
  Future<Map<String, dynamic>> invokeFunction(
    String fn, {
    Map<String, dynamic>? body,
  }) async => {};

  @override
  Future<String> uploadStorage(
    String bucket,
    String path,
    List<int> bytes, {
    String? contentType,
  }) async {
    storageCalls.add('$bucket/$path');
    return path;
  }
}

void main() {
  group('SupabaseBookingRepository - Payment Proofs', () {
    late MockAppSupabase mockSupabase;
    late SupabaseBookingRepository repository;

    setUp(() {
      mockSupabase = MockAppSupabase();
      repository = SupabaseBookingRepository(mockSupabase);
    });

    test('fetchPayoutChannels returns list of PayoutChannel on query success', () async {
      mockSupabase.queryResponse = [
        {
          'id': 1,
          'channel': 'VODAFONE_CASH',
          'display_name_ar': 'فودافون كاش',
          'account_number': '01000000000',
          'holder_name': 'الكنيسة',
        },
        {
          'id': 2,
          'channel': 'INSTAPAY',
          'display_name_ar': 'إنستاباي',
          'account_number': '01011112222',
          'holder_name': 'الكنيسة',
        },
      ];

      final result = await repository.fetchPayoutChannels();
      expect(result.isRight, isTrue);
      final channels = result.rightOrNull!;
      expect(channels.length, 2);
      expect(channels.first.channel, PaymentChannel.vodafoneCash);
      expect(channels.first.accountNumber, '01000000000');
      expect(mockSupabase.queryTables, contains('payout_channels'));
    });

    test('submitPaymentProof calls submit_payment_proof RPC and returns proof id', () async {
      mockSupabase.rpcResponse = 42;

      final input = PaymentProofInput(
        bookingId: 101,
        channel: PaymentChannel.vodafoneCash,
        senderPhone: '01000000000',
        referenceNumber: 'REF123',
        amount: 150,
        imagePath: '1/101/proof.jpg',
      );

      final result = await repository.submitPaymentProof(input);
      expect(result.isRight, isTrue);
      expect(result.rightOrNull, 42);
      expect(mockSupabase.rpcCalls, contains('submit_payment_proof'));
      expect(mockSupabase.rpcParams['p_booking_id'], 101);
      expect(mockSupabase.rpcParams['p_channel'], 'VODAFONE_CASH');
      expect(mockSupabase.rpcParams['p_image_path'], '1/101/proof.jpg');
    });

    test('submitPaymentProof maps 42501 FORBIDDEN to AuthFailure without raw leak', () async {
      mockSupabase.rpcError = const PostgrestException(
        message: 'FORBIDDEN',
        code: '42501',
      );

      final input = PaymentProofInput(
        bookingId: 101,
        channel: PaymentChannel.vodafoneCash,
        senderPhone: '01000000000',
        referenceNumber: 'REF123',
        amount: 150,
        imagePath: '1/101/proof.jpg',
      );

      final result = await repository.submitPaymentProof(input);
      expect(result.isLeft, isTrue);
      final failure = result.leftOrNull!;
      expect(failure.code, '42501');
      expect(failure, isA<Failure>());
    });

    test('submitPaymentProof maps P0001 BAD_REQUEST to BookingFailure without raw leak', () async {
      mockSupabase.rpcError = const PostgrestException(
        message: 'BAD_REQUEST',
        code: 'P0001',
      );

      final input = PaymentProofInput(
        bookingId: 101,
        channel: PaymentChannel.vodafoneCash,
        senderPhone: '01000000000',
        referenceNumber: 'REF123',
        amount: 150,
        imagePath: null,
      );

      final result = await repository.submitPaymentProof(input);
      expect(result.isLeft, isTrue);
      final failure = result.leftOrNull!;
      expect(failure, isA<BookingFailure>());
      expect(failure.code, 'P0001');
    });
  });
}
