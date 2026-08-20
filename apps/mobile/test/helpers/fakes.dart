import 'package:mobile/core/either.dart';
import 'package:mobile/core/failure.dart';
import 'package:mobile/models/available_slot.dart';
import 'package:mobile/models/booking.dart';
import 'package:mobile/models/booking_checkout_session.dart';
import 'package:mobile/repositories/booking_repository.dart';

class FakeBookingRepository implements BookingRepository {
  FakeBookingRepository({
    this.bookings = const [],
    this.services = const [],
    this.slots = const [],
    this.checkoutUrl,
  });
  List<Booking> bookings;
  List<Map<String, dynamic>> services;
  List<Map<String, dynamic>> slots;
  String? checkoutUrl;
  final List<String> calls = [];

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
  Future<Either<Failure, BookingCheckoutSession>> reserveAndPay({
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

    return Right(
      BookingCheckoutSession(
        booking: booking,
        checkoutUrl: isFree ? null : checkoutUrl,
        paymentId: isFree ? null : 1001,
        isConfirmed: isFree,
      ),
    );
  }

  @override
  Future<Either<Failure, BookingCheckoutSession>> retryCheckout(
    int bookingId,
  ) async {
    calls.add('retryCheckout');
    final booking = bookings.firstWhere(
      (b) => b.id == bookingId,
      orElse: () => fakeBooking,
    );
    if (checkoutUrl == null) {
      return Left(
        CheckoutFailure('No checkout URL configured', bookingId: bookingId),
      );
    }
    return Right(
      BookingCheckoutSession(
        booking: booking,
        checkoutUrl: checkoutUrl,
        paymentId: 1001,
        isConfirmed: false,
      ),
    );
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

