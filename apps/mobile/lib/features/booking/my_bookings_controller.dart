import 'dart:async';

class MyBookingsController {
  final StreamController<String> _updates =
      StreamController<String>.broadcast();
  Stream<String> get updates => _updates.stream;

  void applyPayload(Map<String, dynamic> payload) {
    final newRow = payload['new'] as Map<String, dynamic>?;
    if (newRow == null) return;
    _updates.add(newRow['status'] as String);
  }

  void dispose() => _updates.close();
}
