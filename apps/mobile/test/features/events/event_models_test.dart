import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/events/domain/event_models.dart';

void main() {
  group('Event Booking Models Unit Tests', () {
    test('EventTypeModel converts piastres to EGP correctly', () {
      final model = EventTypeModel.fromJson({
        'id': 1,
        'name_ar': 'إكليل وزفاف',
        'base_price_piastres': 150000,
        'is_active': true,
      });

      expect(model.id, equals(1));
      expect(model.nameAr, equals('إكليل وزفاف'));
      expect(model.basePricePiastres, equals(150000));
      expect(model.basePriceEgp, equals(1500.0));
    });

    test('ExtraServiceModel quantity and pricing calculations', () {
      final service = ExtraServiceModel.fromJson({
        'id': 10,
        'name_ar': 'تصوير فيديو',
        'unit_price_piastres': 50000,
      });

      final selected = SelectedExtraService(service: service, quantity: 2);

      expect(selected.totalPricePiastres, equals(100000));
      expect(selected.totalPriceEgp, equals(1000.0));
    });

    test('EventBookingModel calculates remaining balance correctly', () {
      final booking = EventBookingModel.fromJson({
        'id': 99,
        'status': 'PARTIALLY_PAID',
        'total_price_piastres': 200000,
        'paid_amount_piastres': 50000,
        'created_at': '2026-09-01T10:00:00Z',
      });

      expect(booking.totalPriceEgp, equals(2000.0));
      expect(booking.paidAmountEgp, equals(500.0));
      expect(booking.remainingEgp, equals(1500.0));
    });
  });
}
