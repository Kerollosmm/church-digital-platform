import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/booking/my_bookings_controller.dart';

void main() {
  test(
    'realtime controller emits updated status from channel payload',
    () async {
      final controller = MyBookingsController();
      final updates = <String>[];
      final sub = controller.updates.listen(updates.add);
      controller.applyPayload({
        'new': {'id': 7, 'status': 'AWAITING_CALL'},
      });
      await Future<void>.delayed(Duration.zero);
      expect(updates, ['AWAITING_CALL']);
      sub.cancel();
      controller.dispose();
    },
  );
}
