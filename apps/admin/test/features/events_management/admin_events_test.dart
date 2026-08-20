import 'package:flutter_test/flutter_test.dart';
import 'package:admin/features/events_management/domain/admin_event_models.dart';

void main() {
  group('Admin Event Booking Models Unit Tests', () {
    test('AdminEventBookingModel parses json and calculates remaining EGP balance', () {
      final model = AdminEventBookingModel.fromJson({
        'id': 500,
        'status': 'PENDING_PAYMENT',
        'total_price_piastres': 300000,
        'paid_amount_piastres': 100000,
        'notes': 'اختبار الإدارة',
        'created_at': '2026-09-01T12:00:00Z',
        'users': {
          'full_name': 'مينا يوسف',
          'phone': '+201200000000',
        },
      });

      expect(model.id, equals(500));
      expect(model.userName, equals('مينا يوسف'));
      expect(model.totalPriceEgp, equals(3000.0));
      expect(model.paidAmountEgp, equals(1000.0));
      expect(model.remainingEgp, equals(2000.0));
    });

    test('VenueResourceModel parses json correctly', () {
      final venue = VenueResourceModel.fromJson({
        'id': 10,
        'name_ar': 'قاعة العزاء والضيوف',
        'capacity': 250,
        'is_active': true,
      });

      expect(venue.id, equals(10));
      expect(venue.nameAr, equals('قاعة العزاء والضيوف'));
      expect(venue.capacity, equals(250));
    });
  });
}
