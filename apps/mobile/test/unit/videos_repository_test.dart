import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic>? parsePurchaseRpcResult(dynamic data) {
  if (data == null) return null;
  if (data is num) return {'id': data.toInt()};
  if (data is String) {
    final parsed = int.tryParse(data);
    return parsed != null ? {'id': parsed} : null;
  }
  if (data is Map) {
    final id = data['id'];
    if (id != null) return Map<String, dynamic>.from(data);
    return null;
  }
  final parsed = int.tryParse(data.toString());
  return parsed != null ? {'id': parsed} : null;
}

void main() {
  test('parsePurchaseRpcResult handles num', () {
    expect(parsePurchaseRpcResult(42), equals({'id': 42}));
  });

  test('parsePurchaseRpcResult handles numeric string', () {
    expect(parsePurchaseRpcResult('123'), equals({'id': 123}));
  });

  test('parsePurchaseRpcResult handles map with valid id', () {
    expect(parsePurchaseRpcResult({'id': 50}), equals({'id': 50}));
  });

  test('parsePurchaseRpcResult returns null on unparsable input or invalid map', () {
    expect(parsePurchaseRpcResult('not-a-number'), isNull);
    expect(parsePurchaseRpcResult({'id': null}), isNull);
    expect(parsePurchaseRpcResult(null), isNull);
  });
}
