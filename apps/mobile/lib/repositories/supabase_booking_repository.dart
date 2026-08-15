import 'dart:developer' as developer;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/either.dart';
import '../core/failure.dart';
import '../models/available_slot.dart';
import '../models/booking.dart';
import '../models/booking_checkout_session.dart';
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
  Future<Either<Failure, BookingCheckoutSession>> reserveAndPay({
    required int slotId,
    bool whatsappOptIn = false,
  }) async {
    // 1. Atomic reservation via book_slot RPC
    final Booking booking;
    try {
      final data = await _supabase.rpc('book_slot', {
        'p_slot_id': slotId,
        'p_opt_in': whatsappOptIn,
      });
      booking = Booking.fromJson(Map<String, dynamic>.from(data as Map));
    } on PostgrestException catch (e) {
      developer.log('book_slot RPC failed: ${e.message}', name: 'BookingRepository');
      if (e.code == '28000' || e.message.toUpperCase().contains('AUTH_REQUIRED')) {
        return Left(AuthFailure(e.message, code: e.code, originalError: e));
      }
      return Left(BookingFailure(e.message, code: e.code, originalError: e));
    } catch (e) {
      developer.log('book_slot unexpected error: $e', name: 'BookingRepository');
      return Left(BookingFailure(e.toString(), originalError: e));
    }

    // 2. Free booking -> immediately confirmed (no Paymob checkout dispatch)
    if (booking.paidAmount == 0) {
      return Right(
        BookingCheckoutSession(
          booking: booking,
          checkoutUrl: null,
          paymentId: null,
          isConfirmed: true,
        ),
      );
    }

    // 3. Paid booking -> dispatch Paymob checkout intent
    try {
      final checkout = await _createCheckout(booking.id);
      final checkoutUrl = checkout?['checkout_url'] as String?;
      final paymentId = checkout?['payment_id'] as int?;

      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        return Left(
          CheckoutFailure(
            'Missing checkout URL in Paymob response',
            bookingId: booking.id,
          ),
        );
      }

      return Right(
        BookingCheckoutSession(
          booking: booking,
          checkoutUrl: checkoutUrl,
          paymentId: paymentId,
          isConfirmed: false,
        ),
      );
    } catch (e) {
      developer.log(
        'paymob-checkout failed for booking #${booking.id}: $e',
        name: 'BookingRepository',
      );
      return Left(
        CheckoutFailure(
          'Failed to initialize payment checkout: $e',
          bookingId: booking.id,
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<Either<Failure, BookingCheckoutSession>> retryCheckout(int bookingId) async {
    try {
      final checkout = await _createCheckout(bookingId);
      final checkoutUrl = checkout?['checkout_url'] as String?;
      final paymentId = checkout?['payment_id'] as int?;

      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        return Left(
          CheckoutFailure(
            'Missing checkout URL in Paymob response',
            bookingId: bookingId,
          ),
        );
      }

      return Right(
        BookingCheckoutSession(
          booking: Booking(id: bookingId, status: 'PENDING_PAYMENT'),
          checkoutUrl: checkoutUrl,
          paymentId: paymentId,
          isConfirmed: false,
        ),
      );
    } catch (e) {
      developer.log(
        'retryCheckout failed for booking #$bookingId: $e',
        name: 'BookingRepository',
      );
      return Left(
        CheckoutFailure(
          'Failed to retry payment checkout: $e',
          bookingId: bookingId,
          originalError: e,
        ),
      );
    }
  }

  /// Internal checkout creation helper (hidden from presentation interface)
  Future<Map<String, dynamic>?> _createCheckout(int bookingId) async {
    final data = await _supabase.invokeFunction(
      'paymob-checkout',
      body: {'booking_id': bookingId},
    );
    return data;
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
  Future<Either<Failure, BookingCheckoutSession>> reserveAndPay({
    required int slotId,
    bool whatsappOptIn = false,
  }) async => const Left(BookingFailure('Empty booking repository'));
  @override
  Future<Either<Failure, BookingCheckoutSession>> retryCheckout(
    int bookingId,
  ) async => const Left(BookingFailure('Empty booking repository'));
  @override
  Future<void> cancelBooking(int bookingId) async => Future.value();
  @override
  Future<void> confirmBooking(int bookingId) async => Future.value();
  @override
  Future<void> completeBooking(int bookingId) async => Future.value();
}
