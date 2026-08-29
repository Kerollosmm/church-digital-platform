import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/event_booking.dart';

void main() {
  group('EventBooking Model', () {
    test('fromJson parses assigned priest and venue correctly', () {
      final json = {
        'id': 'booking-001',
        'customer_id': 'user-001',
        'event_type_id': 'event-type-001',
        'event_types': {'name_ar': 'معمودية مباركة'},
        'assigned_venue_id': 'venue-001',
        'venues_resources': {'name_ar': 'المعمودية الكبرى'},
        'assigned_priest_id': 7501,
        'priests': {'name': 'أبونا أنطونيوس'},
        'start_time': '2026-09-10T10:00:00.000Z',
        'end_time': '2026-09-10T12:00:00.000Z',
        'status': 'CONFIRMED',
        'base_price_piastres': 25000,
        'total_price_piastres': 25000,
        'paid_amount_piastres': 25000,
      };

      final booking = EventBooking.fromJson(json);

      expect(booking.id, equals('booking-001'));
      expect(booking.eventTypeName, equals('معمودية مباركة'));
      expect(booking.assignedVenueId, equals('venue-001'));
      expect(booking.venueName, equals('المعمودية الكبرى'));
      expect(booking.assignedPriestId, equals(7501));
      expect(booking.priestName, equals('أبونا أنطونيوس'));
      expect(booking.status, equals('CONFIRMED'));
      expect(booking.totalPriceEgp, equals(250.0));
    });

    test('fromJson handles null priest and venue gracefully', () {
      final json = {
        'id': 'booking-002',
        'customer_id': 'user-002',
        'event_type_id': 'event-type-002',
        'event_type_name': 'إكليل مقدس',
        'start_time': '2026-09-10T18:00:00.000Z',
        'end_time': '2026-09-10T20:00:00.000Z',
        'status': 'SUBMITTED',
      };

      final booking = EventBooking.fromJson(json);

      expect(booking.id, equals('booking-002'));
      expect(booking.eventTypeName, equals('إكليل مقدس'));
      expect(booking.assignedVenueId, isNull);
      expect(booking.venueName, isNull);
      expect(booking.assignedPriestId, isNull);
      expect(booking.priestName, isNull);
      expect(booking.status, equals('SUBMITTED'));
    });
  });
}
