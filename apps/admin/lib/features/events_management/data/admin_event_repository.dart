import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/admin_event_models.dart';

abstract class AdminEventRepository {
  Future<List<AdminEventBookingModel>> fetchEventBookingsQueue({String? statusFilter});
  Future<List<VenueResourceModel>> fetchVenues();
  Future<void> confirmBooking({
    required int bookingId,
    required int venueId,
    required DateTime confirmedStart,
    int durationMinutes = 120,
  });
  Future<void> rejectBooking({
    required int bookingId,
    required String reason,
  });
  Future<int> recordCashPayment({
    required int bookingId,
    required int amountPiastres,
    String? receiptRef,
    String? notes,
  });
}

class SupabaseAdminEventRepository implements AdminEventRepository {
  final SupabaseClient _client;

  SupabaseAdminEventRepository(this._client);

  @override
  Future<List<AdminEventBookingModel>> fetchEventBookingsQueue({String? statusFilter}) async {
    final query = _client
        .from('bookings')
        .select('*, users(full_name, phone)')
        .isFilter('slot_id', null);

    if (statusFilter != null && statusFilter.isNotEmpty) {
      final res = await query.eq('status', statusFilter).order('created_at', ascending: false);
      return (res as List).map((r) => AdminEventBookingModel.fromJson(r)).toList();
    }

    final res = await query.order('created_at', ascending: false);
    return (res as List).map((r) => AdminEventBookingModel.fromJson(r)).toList();
  }

  @override
  Future<List<VenueResourceModel>> fetchVenues() async {
    final res = await _client
        .from('venues_resources')
        .select()
        .eq('is_active', true);

    return (res as List).map((r) => VenueResourceModel.fromJson(r)).toList();
  }

  @override
  Future<void> confirmBooking({
    required int bookingId,
    required int venueId,
    required DateTime confirmedStart,
    int durationMinutes = 120,
  }) async {
    await _client.rpc('admin_confirm_booking', params: {
      'p_booking_id': bookingId,
      'p_venue_id': venueId,
      'p_confirmed_start': confirmedStart.toIso8601String(),
      'p_duration_minutes': durationMinutes,
    });
  }

  @override
  Future<void> rejectBooking({
    required int bookingId,
    required String reason,
  }) async {
    await _client.rpc('admin_reject_booking', params: {
      'p_booking_id': bookingId,
      'p_rejection_reason': reason,
    });
  }

  @override
  Future<int> recordCashPayment({
    required int bookingId,
    required int amountPiastres,
    String? receiptRef,
    String? notes,
  }) async {
    final res = await _client.rpc('admin_record_cash_payment', params: {
      'p_booking_id': bookingId,
      'p_amount_piastres': amountPiastres,
      'p_receipt_ref': receiptRef,
      'p_notes': notes,
    });

    return (res as num).toInt();
  }
}

final adminEventRepositoryProvider = Provider<AdminEventRepository>((ref) {
  return SupabaseAdminEventRepository(Supabase.instance.client);
});
