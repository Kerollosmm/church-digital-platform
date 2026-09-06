import '../core/either.dart';
import '../core/failure.dart';
import '../models/event_booking.dart';

abstract interface class EventBookingRepository {
  Future<Either<Failure, List<EventType>>> fetchEventTypes();
  Future<Either<Failure, List<ExtraService>>> fetchExtraServicesForEvent(
    String eventTypeId,
  );
  Future<Either<Failure, String>> submitEventBooking({
    required String eventTypeId,
    required DateTime startTime,
    required List<Map<String, dynamic>> extraServices,
    String? notes,
  });
  Future<Either<Failure, List<EventBooking>>> fetchMyEventBookings();
}
