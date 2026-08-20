import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/event_models.dart';

abstract class EventBookingRepository {
  Future<List<EventTypeModel>> fetchEventTypes();
  Future<List<ExtraServiceModel>> fetchExtraServices();
  Future<int> submitEventBooking({
    required int eventTypeId,
    required DateTime requestedTime,
    required List<SelectedExtraService> extras,
    String? notes,
  });
  Future<List<EventBookingModel>> fetchMyEventBookings();
  Future<String> initiatePaymobCheckout(int bookingId);
}

class SupabaseEventBookingRepository implements EventBookingRepository {
  final SupabaseClient _client;

  SupabaseEventBookingRepository(this._client);

  @override
  Future<List<EventTypeModel>> fetchEventTypes() async {
    final res = await _client
        .from('event_types')
        .select()
        .eq('is_active', true);
    return (res as List).map((r) => EventTypeModel.fromJson(r)).toList();
  }

  @override
  Future<List<ExtraServiceModel>> fetchExtraServices() async {
    final res = await _client
        .from('extra_services')
        .select()
        .eq('is_active', true);
    return (res as List).map((r) => ExtraServiceModel.fromJson(r)).toList();
  }

  @override
  Future<int> submitEventBooking({
    required int eventTypeId,
    required DateTime requestedTime,
    required List<SelectedExtraService> extras,
    String? notes,
  }) async {
    final extrasJson = extras.map((e) => {
      'extra_service_id': e.service.id,
      'quantity': e.quantity,
    }).toList();

    final res = await _client.rpc('submit_event_booking', params: {
      'p_event_type_id': eventTypeId,
      'p_requested_time': requestedTime.toIso8601String(),
      'p_extras': extrasJson,
      'p_notes': notes,
    });

    return (res as num).toInt();
  }

  @override
  Future<List<EventBookingModel>> fetchMyEventBookings() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    final res = await _client
        .from('bookings')
        .select()
        .eq('user_id', user.id)
        .isFilter('slot_id', null)
        .order('created_at', ascending: false);

    return (res as List).map((r) => EventBookingModel.fromJson(r)).toList();
  }

  @override
  Future<String> initiatePaymobCheckout(int bookingId) async {
    final session = _client.auth.currentSession;
    final token = session?.accessToken;

    final res = await _client.functions.invoke(
      'paymob-checkout',
      body: {'booking_id': bookingId},
      headers: token != null ? {'Authorization': 'Bearer $token'} : null,
    );

    if (res.status != 200) {
      final data = res.data as Map<String, dynamic>?;
      final msg = data?['message_ar'] as String? ?? 'فشل طلب الدفع الإلكتروني';
      throw Exception(msg);
    }

    final data = res.data as Map<String, dynamic>;
    return data['checkout_url'] as String;
  }
}

final eventBookingRepositoryProvider = Provider<EventBookingRepository>((ref) {
  return SupabaseEventBookingRepository(Supabase.instance.client);
});
