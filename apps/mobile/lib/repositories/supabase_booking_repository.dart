import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/either.dart';
import '../core/failure.dart';
import '../models/available_slot.dart';
import '../models/booking.dart';
import '../models/payment_proof.dart';
import '../models/payment_proof_input.dart';
import '../models/payout_channel.dart';
import '../services/app_supabase.dart';
import 'booking_repository.dart';

class SupabaseBookingRepository implements BookingRepository {
  SupabaseBookingRepository(this._supabase);
  final AppSupabase _supabase;

  @override
  Future<List<Map<String, dynamic>>> fetchServices() async =>
      await _supabase.query('v_services');

  @override
  Future<List<Map<String, dynamic>>> fetchSlotsForService(
    int serviceId,
  ) async => await _supabase.query(
    'v_available_slots',
    filters: {'service_id': serviceId},
    orderBy: 'starts_at',
  );

  @override
  Future<List<AvailableSlot>> fetchAvailableSlots() async {
    final rows = await _supabase.query(
      'v_available_slots',
      orderBy: 'starts_at',
    );
    return rows.map(AvailableSlot.fromJson).toList();
  }

  @override
  Future<List<Booking>> fetchMyBookings() async {
    final rows = await _supabase.query(
      'v_my_bookings',
      orderBy: 'created_at',
      ascending: false,
    );
    return rows.map(Booking.fromJson).toList();
  }

  @override
  Future<Either<Failure, Booking>> reserveAndPay({
    required int slotId,
    bool whatsappOptIn = false,
  }) async {
    try {
      final data = await _supabase.rpc('book_slot', {
        'p_slot_id': slotId,
        'p_opt_in': whatsappOptIn,
      });
      final booking = Booking.fromJson(Map<String, dynamic>.from(data as Map));
      return Right(booking);
    } on PostgrestException catch (e) {
      developer.log(
        'book_slot RPC failed: ${e.message}',
        name: 'BookingRepository',
      );
      if (e.code == '28000' ||
          e.message.toUpperCase().contains('AUTH_REQUIRED')) {
        return Left(AuthFailure(e.message, code: e.code, originalError: e));
      }
      return Left(BookingFailure(e.message, code: e.code, originalError: e));
    } catch (e) {
      developer.log(
        'book_slot unexpected error: $e',
        name: 'BookingRepository',
      );
      return Left(BookingFailure(e.toString(), originalError: e));
    }
  }

  @override
  Future<Either<Failure, List<PayoutChannel>>> fetchPayoutChannels() async {
    try {
      final rows = await _supabase.query(
        'payout_channels',
        filters: const {'is_active': true},
        orderBy: 'id',
      );
      final channels = rows.map(PayoutChannel.fromJson).toList();
      return Right(channels);
    } on PostgrestException catch (e) {
      developer.log(
        'fetchPayoutChannels failed: ${e.message}',
        name: 'BookingRepository',
      );
      return Left(BookingFailure(e.message, code: e.code, originalError: e));
    } catch (e) {
      developer.log(
        'fetchPayoutChannels unexpected error: $e',
        name: 'BookingRepository',
      );
      return Left(BookingFailure(e.toString(), originalError: e));
    }
  }

  int? _cachedTenantId;

  Future<int?> _resolveTenantId() async {
    if (_cachedTenantId != null) return _cachedTenantId;
    try {
      final res = await _supabase.rpc('tenant_id', const {});
      if (res is num) {
        _cachedTenantId = res.toInt();
      } else if (res != null) {
        _cachedTenantId = int.parse(res.toString());
      }
    } catch (e) {
      developer.log('tenant_id lookup failed: $e', name: 'BookingRepository');
    }
    return _cachedTenantId;
  }

  @override
  Future<Either<Failure, int>> submitPaymentProof(
    PaymentProofInput input,
  ) async {
    try {
      final res = await _supabase.rpc(
        'submit_payment_proof',
        input.toRpcParams(),
      );
      final proofId = (res is num) ? res.toInt() : int.parse(res.toString());
      return Right(proofId);
    } on PostgrestException catch (e) {
      developer.log(
        'submit_payment_proof RPC failed: ${e.message}',
        name: 'BookingRepository',
      );
      if (e.code == '28000' ||
          e.message.toUpperCase().contains('UNAUTHORIZED')) {
        return Left(AuthFailure(e.message, code: e.code, originalError: e));
      }
      if (e.code == '42501' || e.message.toUpperCase().contains('FORBIDDEN')) {
        return Left(AuthFailure(e.message, code: e.code, originalError: e));
      }
      return Left(BookingFailure(e.message, code: e.code, originalError: e));
    } catch (e) {
      developer.log(
        'submit_payment_proof unexpected error: $e',
        name: 'BookingRepository',
      );
      return Left(BookingFailure(e.toString(), originalError: e));
    }
  }

  @override
  Future<Either<Failure, String>> uploadProofImage({
    required int bookingId,
    required Uint8List bytes,
    required String filename,
  }) async {
    try {
      final tenantId = await _resolveTenantId();
      if (tenantId == null) {
        return const Left(AuthFailure('UNAUTHORIZED', code: '28000'));
      }
      final path = '$tenantId/$bookingId/$filename';
      final res = await _supabase.uploadStorage(
        'payment-proofs',
        path,
        bytes,
        contentType: 'image/jpeg',
      );
      return Right(res);
    } on StorageException catch (e) {
      developer.log(
        'uploadProofImage failed: ${e.message}',
        name: 'BookingRepository',
      );
      return Left(
        BookingFailure(e.message, code: e.statusCode, originalError: e),
      );
    } catch (e) {
      developer.log(
        'uploadProofImage unexpected error: $e',
        name: 'BookingRepository',
      );
      return Left(BookingFailure(e.toString(), originalError: e));
    }
  }

  @override
  Future<Either<Failure, PaymentProof>> fetchLatestProof(int bookingId) async {
    try {
      final rows = await _supabase.query(
        'payment_proofs',
        filters: {'booking_id': bookingId},
        orderBy: 'created_at',
        ascending: false,
      );
      if (rows.isEmpty) {
        return Left(BookingFailure('no proof for booking $bookingId'));
      }
      return Right(PaymentProof.fromJson(rows.first));
    } on PostgrestException catch (e) {
      developer.log(
        'fetchLatestProof failed: ${e.message}',
        name: 'BookingRepository',
      );
      return Left(BookingFailure(e.message, code: e.code, originalError: e));
    } catch (e) {
      developer.log(
        'fetchLatestProof unexpected error: $e',
        name: 'BookingRepository',
      );
      return Left(BookingFailure(e.toString(), originalError: e));
    }
  }

  @override
  Future<Either<Failure, void>> deleteProofImage(String path) async {
    try {
      await _supabase.deleteStorage('payment-proofs', path);
      return const Right(null);
    } on StorageException catch (e) {
      developer.log(
        'deleteProofImage failed: ${e.message}',
        name: 'BookingRepository',
      );
      return Left(
        BookingFailure(e.message, code: e.statusCode, originalError: e),
      );
    } catch (e) {
      developer.log(
        'deleteProofImage unexpected error: $e',
        name: 'BookingRepository',
      );
      return Left(BookingFailure(e.toString(), originalError: e));
    }
  }

  @override
  Future<void> cancelBooking(int bookingId) async =>
      await _supabase.rpc('cancel_booking', {'p_booking_id': bookingId});

  @override
  Future<void> confirmBooking(int bookingId) async =>
      await _supabase.rpc('confirm_booking', {'p_booking_id': bookingId});

  @override
  Future<void> completeBooking(int bookingId) async =>
      await _supabase.rpc('complete_booking', {'p_booking_id': bookingId});
}

class EmptyBookingRepository implements BookingRepository {
  @override
  Future<List<Map<String, dynamic>>> fetchServices() async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchSlotsForService(
    int serviceId,
  ) async => [];
  @override
  Future<List<AvailableSlot>> fetchAvailableSlots() async => [];
  @override
  Future<List<Booking>> fetchMyBookings() async => [];
  @override
  Future<Either<Failure, Booking>> reserveAndPay({
    required int slotId,
    bool whatsappOptIn = false,
  }) async => const Left(BookingFailure('Empty booking repository'));
  @override
  Future<Either<Failure, List<PayoutChannel>>> fetchPayoutChannels() async =>
      const Right([]);
  @override
  Future<Either<Failure, int>> submitPaymentProof(
    PaymentProofInput input,
  ) async => const Left(BookingFailure('Empty booking repository'));
  @override
  Future<Either<Failure, String>> uploadProofImage({
    required int bookingId,
    required Uint8List bytes,
    required String filename,
  }) async => const Left(BookingFailure('Empty booking repository'));
  @override
  Future<Either<Failure, PaymentProof>> fetchLatestProof(int bookingId) async =>
      const Left(BookingFailure('Empty booking repository'));
  @override
  Future<Either<Failure, void>> deleteProofImage(String path) async =>
      const Right(null);
  @override
  Future<void> cancelBooking(int bookingId) async => Future.value();
  @override
  Future<void> confirmBooking(int bookingId) async => Future.value();
  @override
  Future<void> completeBooking(int bookingId) async => Future.value();
}
