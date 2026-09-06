import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/book_slot_result.dart';
import 'package:mobile/models/booking_status.dart';
import 'package:mobile/models/resolved_booking_status.dart';

void main() {
  test('resolver covers every db status', () {
    for (final s in BookingStatus.values) {
      final r = resolveBookingStatus(s);
      expect(r.label, isNotEmpty);
      expect(r.color, isNotNull);
      expect(r.sortWeight, isA<int>());
    }
  });

  test('bookSlot maps real error codes', () {
    expect(
      bookSlotErrorCode('SLOT_UNAVAILABLE'),
      BookSlotStatus.slotUnavailable,
    );
    expect(bookSlotErrorCode('SLOT_FULL'), BookSlotStatus.slotFull);
    expect(
      bookSlotErrorCode('ALREADY_BOOKED_SLOT'),
      BookSlotStatus.alreadyBooked,
    );
    expect(
      bookSlotErrorCode('TOO_MANY_ACTIVE_BOOKINGS'),
      BookSlotStatus.tooManyActive,
    );
    expect(bookSlotErrorCode('anything else'), BookSlotStatus.unknown);
  });
}
