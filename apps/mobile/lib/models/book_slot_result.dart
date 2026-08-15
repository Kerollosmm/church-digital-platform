import 'booking.dart';

enum BookSlotStatus {
  success,
  slotUnavailable,
  slotFull,
  alreadyBooked,
  tooManyActive,
  unknown,
}

class BookSlotResult {
  const BookSlotResult({required this.status, this.message = '', this.booking});
  final BookSlotStatus status;
  final String message;
  final Booking? booking;
}

BookSlotStatus bookSlotErrorCode(String messagePrefix) {
  final m = messagePrefix.toUpperCase();
  if (m.contains('SLOT_UNAVAILABLE')) return BookSlotStatus.slotUnavailable;
  if (m.contains('SLOT_FULL')) return BookSlotStatus.slotFull;
  if (m.contains('ALREADY_BOOKED_SLOT')) return BookSlotStatus.alreadyBooked;
  if (m.contains('TOO_MANY_ACTIVE_BOOKINGS'))
    return BookSlotStatus.tooManyActive;
  return BookSlotStatus.unknown;
}
