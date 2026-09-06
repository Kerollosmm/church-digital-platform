import 'package:flutter_test/flutter_test.dart';
import 'package:admin/core/money_format.dart';

void main() {
  test('formats whole piastres without decimals', () {
    expect(formatEgp(5000), '50 ج.م');
  });
  test('formats fractional piastres with 2 decimals', () {
    expect(formatEgp(5050), '50.50 ج.م');
  });
  test('converts EGP entry to piastres', () {
    expect(egpToPiastres(50), 5000);
    expect(egpToPiastres(49.99), 4999);
  });
  test('zero stays zero', () {
    expect(formatEgp(0), '0 ج.م');
    expect(egpToPiastres(0), 0);
  });
}
