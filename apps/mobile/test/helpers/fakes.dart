import 'dart:typed_data';
import 'package:mobile/core/either.dart';
import 'package:mobile/core/failure.dart';
import 'package:mobile/models/available_slot.dart';
import 'package:mobile/models/booking.dart';
import 'package:mobile/models/payment_proof_input.dart';
import 'package:mobile/models/payout_channel.dart';
import 'package:mobile/repositories/booking_repository.dart';

class FakeBookingRepository implements BookingRepository {
  FakeBookingRepository({
    this.bookings = const [],
    this.services = const [],
    this.slots = const [],
    this.payoutChannels = const [],
    this.checkoutUrl,
  });
  List<Booking> bookings;
  List<Map<String, dynamic>> services;
  List<Map<String, dynamic>> slots;
  List<PayoutChannel> payoutChannels;
  String? checkoutUrl;
  final List<String> calls = [];
  PaymentProofInput? lastSubmittedProof;

  @override
  Future<Either<Failure, List<PayoutChannel>>> fetchPayoutChannels() async {
    calls.add('fetchPayoutChannels');
    return Right(payoutChannels);
  }

  @override
  Future<Either<Failure, int>> submitPaymentProof(PaymentProofInput input) async {
    calls.add('submitPaymentProof');
    lastSubmittedProof = input;
    return const Right(1);
  }

  @override
  Future<Either<Failure, String>> uploadProofImage({
    required int bookingId,
    required Uint8List bytes,
    required String filename,
  }) async {
    calls.add('uploadProofImage');
    return Right('1/$bookingId/$filename');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchServices() async {
    calls.add('fetchServices');
    return services;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSlotsForService(int serviceId) async {
    calls.add('fetchSlotsForService');
    return slots;
  }

  @override
  Future<List<Booking>> fetchMyBookings() async {
    calls.add('fetchMyBookings');
    return bookings;
  }

  @override
  Future<Either<Failure, Booking>> reserveAndPay({
    required int slotId,
    bool whatsappOptIn = false,
  }) async {
    calls.add('reserveAndPay');
    final slot = slots.cast<Map<String, dynamic>?>().firstWhere(
      (s) => s != null && (s['id'] == slotId || s['slot_id'] == slotId),
      orElse: () => null,
    );

    final isFree =
        (slot?['price'] as num?)?.toInt() == 0 ||
        (slot == null && checkoutUrl == null);

    final booking = bookings.isNotEmpty
        ? bookings.first
        : Booking(
            id: slotId,
            status: isFree ? 'CONFIRMED' : 'PENDING_PAYMENT',
            paidAmount: isFree ? 0 : 50,
          );

    return Right(booking);
  }

  @override
  Future<void> cancelBooking(int bookingId) async {
    calls.add('cancelBooking');
  }

  @override
  Future<void> confirmBooking(int bookingId) async {}
  @override
  Future<void> completeBooking(int bookingId) async {}
  @override
  Future<List<AvailableSlot>> fetchAvailableSlots() async => [];
}

final fakeBooking = Booking(
  id: 5,
  status: 'CONFIRMED',
  serviceName: 'قداس',
  paidAmount: 0,
);
