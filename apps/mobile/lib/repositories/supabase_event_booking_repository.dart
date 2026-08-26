import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/either.dart';
import '../core/failure.dart';
import '../models/event_booking.dart';
import 'event_booking_repository.dart';

class SupabaseEventBookingRepository implements EventBookingRepository {
  SupabaseEventBookingRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<Either<Failure, List<EventType>>> fetchEventTypes() async {
    try {
      final res = await _client
          .from('event_types')
          .select()
          .eq('is_active', true)
          .order('name_ar');
      final list = (res as List<dynamic>)
          .map((e) => EventType.fromJson(e as Map<String, dynamic>))
          .toList();
      return Right(list);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<ExtraService>>> fetchExtraServicesForEvent(
    String eventTypeId,
  ) async {
    try {
      final res = await _client
          .from('event_type_extra_services')
          .select('extra_services(*)')
          .eq('event_type_id', eventTypeId);

      final list = <ExtraService>[];
      for (final item in res as List<dynamic>) {
        final extraMap = item['extra_services'] as Map<String, dynamic>?;
        if (extraMap != null && (extraMap['is_active'] as bool? ?? true)) {
          list.add(ExtraService.fromJson(extraMap));
        }
      }
      return Right(list);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, String>> submitEventBooking({
    required String eventTypeId,
    required DateTime startTime,
    required List<Map<String, dynamic>> extraServices,
    String? notes,
  }) async {
    try {
      final bookingId = await _client.rpc(
        'submit_event_booking',
        params: {
          'p_event_type_id': eventTypeId,
          'p_start_time': startTime.toIso8601String(),
          'p_extra_services': extraServices,
          'p_notes': notes,
        },
      );
      return Right(bookingId.toString());
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<EventBooking>>> fetchMyEventBookings() async {
    try {
      final res = await _client
          .from('event_bookings')
          .select('*, event_types(name_ar), venues_resources(name_ar)')
          .order('created_at', ascending: false);
      final list = (res as List<dynamic>)
          .map((e) => EventBooking.fromJson(e as Map<String, dynamic>))
          .toList();
      return Right(list);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
