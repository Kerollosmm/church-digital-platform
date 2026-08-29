import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/result.dart';
import 'event_booking_admin_models.dart';

abstract interface class EventBookingsAdminRepository {
  Future<Either<Failure, List<EventBookingAdminItem>>> fetchEventBookings({
    String? statusFilter,
  });
  Future<Either<Failure, List<VenueResourceItem>>> fetchVenues();
  Future<Either<Failure, List<PriestAdminItem>>> fetchPriests();
  Future<Either<Failure, List<PriestAdminItem>>> getAvailablePriests({
    required DateTime startTime,
    required DateTime endTime,
  });
  Future<Either<Failure, void>> assignPriestAndVenue({
    required String bookingId,
    required String venueId,
    required int priestId,
    String? overrideNotes,
  });
  Future<Either<Failure, List<PriestScheduleItem>>> fetchPriestSchedules({
    DateTime? from,
    DateTime? to,
  });
  Future<Either<Failure, void>> confirmBooking({
    required String bookingId,
    required String venueId,
    DateTime? confirmedStart,
    DateTime? confirmedEnd,
    String? adminNote,
  });
  Future<Either<Failure, void>> rejectBooking({
    required String bookingId,
    required String rejectionReason,
  });
  Future<Either<Failure, void>> recordCashPayment({
    required String bookingId,
    required int amountPiastres,
    String? collectorNote,
  });
}

class SupabaseEventBookingsAdminRepository
    implements EventBookingsAdminRepository {
  SupabaseEventBookingsAdminRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<Either<Failure, List<EventBookingAdminItem>>> fetchEventBookings({
    String? statusFilter,
  }) async {
    try {
      var query = _client
          .from('event_bookings')
          .select(
            '*, event_types(name_ar), venues_resources(name_ar), users(name, phone), priests(name)',
          );

      if (statusFilter != null && statusFilter.isNotEmpty) {
        query = query.eq('status', statusFilter);
      }

      final res = await query.order('created_at', ascending: false);
      final list = (res as List<dynamic>)
          .map((e) => EventBookingAdminItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return Right(list);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<VenueResourceItem>>> fetchVenues() async {
    try {
      final res = await _client
          .from('venues_resources')
          .select()
          .eq('is_active', true)
          .order('name_ar');
      final list = (res as List<dynamic>)
          .map((e) => VenueResourceItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return Right(list);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<PriestAdminItem>>> fetchPriests() async {
    try {
      final res = await _client
          .from('priests')
          .select()
          .isFilter('deleted_at', null)
          .order('name');
      final list = (res as List<dynamic>)
          .map((e) => PriestAdminItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return Right(list);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<PriestAdminItem>>> getAvailablePriests({
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      final res = await _client.rpc(
        'get_available_priests',
        params: {
          'p_start_time': startTime.toIso8601String(),
          'p_end_time': endTime.toIso8601String(),
        },
      );
      final list = (res as List<dynamic>)
          .map((e) => PriestAdminItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return Right(list);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> assignPriestAndVenue({
    required String bookingId,
    required String venueId,
    required int priestId,
    String? overrideNotes,
  }) async {
    try {
      await _client.rpc(
        'admin_assign_priest_and_venue',
        params: {
          'p_booking_id': bookingId,
          'p_venue_id': venueId,
          'p_priest_id': priestId,
          'p_override_notes': overrideNotes,
        },
      );
      return const Right(null);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<PriestScheduleItem>>> fetchPriestSchedules({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final res = await _client
          .from('priest_schedules')
          .select('*, priests(name)')
          .order('created_at', ascending: false);
      final list = (res as List<dynamic>)
          .map((e) => PriestScheduleItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return Right(list);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> confirmBooking({
    required String bookingId,
    required String venueId,
    DateTime? confirmedStart,
    DateTime? confirmedEnd,
    String? adminNote,
  }) async {
    try {
      await _client.rpc(
        'admin_confirm_booking',
        params: {
          'p_booking_id': bookingId,
          'p_venue_id': venueId,
          'p_confirmed_start': confirmedStart?.toIso8601String(),
          'p_confirmed_end': confirmedEnd?.toIso8601String(),
          'p_admin_note': adminNote,
        },
      );
      return const Right(null);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> rejectBooking({
    required String bookingId,
    required String rejectionReason,
  }) async {
    try {
      await _client.rpc(
        'admin_reject_booking',
        params: {
          'p_booking_id': bookingId,
          'p_rejection_reason': rejectionReason,
        },
      );
      return const Right(null);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> recordCashPayment({
    required String bookingId,
    required int amountPiastres,
    String? collectorNote,
  }) async {
    try {
      await _client.rpc(
        'admin_record_cash_payment',
        params: {
          'p_booking_id': bookingId,
          'p_amount_piastres': amountPiastres,
          'p_collector_note': collectorNote,
        },
      );
      return const Right(null);
    } catch (e) {
      return Left(Failure(code: 'INTERNAL', message: e.toString()));
    }
  }
}
