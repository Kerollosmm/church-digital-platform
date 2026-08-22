import 'dart:typed_data';
import '../core/either.dart';
import '../core/failure.dart';
import '../models/available_slot.dart';
import '../models/booking.dart';
import '../models/payment_proof_input.dart';
import '../models/payout_channel.dart';

abstract interface class BookingRepository {
  Future<List<Map<String, dynamic>>> fetchServices();
  Future<List<Map<String, dynamic>>> fetchSlotsForService(int serviceId);
  Future<List<AvailableSlot>> fetchAvailableSlots();
  Future<List<Booking>> fetchMyBookings();

  /// Single public entrypoint for reserving a slot.
  Future<Either<Failure, Booking>> reserveAndPay({
    required int slotId,
    bool whatsappOptIn = false,
  });

  Future<Either<Failure, List<PayoutChannel>>> fetchPayoutChannels();
  Future<Either<Failure, int>> submitPaymentProof(PaymentProofInput input);
  Future<Either<Failure, String>> uploadProofImage({
    required int bookingId,
    required Uint8List bytes,
    required String filename,
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
