import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/available_slot.dart';
import '../models/booking.dart';
import '../models/book_slot_result.dart';
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
  Future<BookSlotResult> bookSlot({
    required int slotId,
    required bool optIn,
  }) async {
    try {
      final data = await _supabase.rpc('book_slot', {
        'p_slot_id': slotId,
        'p_opt_in': optIn,
      });
      return BookSlotResult(
        status: BookSlotStatus.success,
        booking: Booking.fromJson(Map<String, dynamic>.from(data as Map)),
      );
    } on PostgrestException catch (e) {
      return BookSlotResult(
        status: bookSlotErrorCode(e.message),
        message: e.message,
      );
    }
  }

  @override
  Future<Map<String, dynamic>?> createCheckout(int bookingId) async {
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
  Future<BookSlotResult> bookSlot({
    required int slotId,
    required bool optIn,
  }) async => const BookSlotResult(status: BookSlotStatus.unknown);
  @override
  Future<Map<String, dynamic>?> createCheckout(int bookingId) async => null;
  @override
  Future<void> cancelBooking(int bookingId) async => throw UnimplementedError();
  @override
  Future<void> confirmBooking(int bookingId) async =>
      throw UnimplementedError();
  @override
  Future<void> completeBooking(int bookingId) async =>
      throw UnimplementedError();
}
