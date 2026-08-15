import '../models/available_slot.dart';
import '../models/booking.dart';
import '../models/book_slot_result.dart';

abstract interface class BookingRepository {
  Future<List<Map<String, dynamic>>> fetchServices();
  Future<List<Map<String, dynamic>>> fetchSlotsForService(int serviceId);
  Future<List<AvailableSlot>> fetchAvailableSlots();
  Future<List<Booking>> fetchMyBookings();
  Future<BookSlotResult> bookSlot({required int slotId, required bool optIn});
  Future<Map<String, dynamic>?> createCheckout(int bookingId);
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
