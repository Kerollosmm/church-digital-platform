import '../core/either.dart';
import '../core/failure.dart';
import '../models/available_slot.dart';
import '../models/booking.dart';
import '../models/booking_checkout_session.dart';

abstract interface class BookingRepository {
  Future<List<Map<String, dynamic>>> fetchServices();
  Future<List<Map<String, dynamic>>> fetchSlotsForService(int serviceId);
  Future<List<AvailableSlot>> fetchAvailableSlots();
  Future<List<Booking>> fetchMyBookings();

  /// Single public entrypoint for reserving and initiating payment for a slot.
  Future<Either<Failure, BookingCheckoutSession>> reserveAndPay({
    required int slotId,
    bool whatsappOptIn = false,
  });

  Future<void> cancelBooking(int bookingId);
  Future<void> confirmBooking(int bookingId);
  Future<void> completeBooking(int bookingId);
}

extension LegacyBookingRepository on BookingRepository {
  Future<List<Map<String, dynamic>>> services() => fetchServices();
  Future<List<Map<String, dynamic>>> slotsForService(int serviceId) =>
      fetchSlotsForService(serviceId);
  Future<List<Map<String, dynamic>>> myBookings() async {
    final list = await fetchMyBookings();
    return list
        .map(
          (b) => <String, dynamic>{
            'id': b.id,
            'status': b.status,
            'service_name': b.serviceName,
            'paid_amount': b.paidAmount,
            'created_at': b.createdAt?.toIso8601String(),
          },
        )
        .toList();
  }
}
