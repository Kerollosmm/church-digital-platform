import 'booking.dart';

class BookingCheckoutSession {
  final Booking booking;
  final String? checkoutUrl;
  final int? paymentId;
  final bool isConfirmed;

  const BookingCheckoutSession({
    required this.booking,
    this.checkoutUrl,
    this.paymentId,
    this.isConfirmed = false,
  });

  Map<String, dynamic> toJson() => {
    'booking': booking.toJson(),
    'checkout_url': checkoutUrl,
    'payment_id': paymentId,
    'is_confirmed': isConfirmed,
  };
}
