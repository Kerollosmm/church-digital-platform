/// All backend money is integer piastres (1 EGP = 100).
/// UI displays EGP; inputs collected in EGP are converted at the seam.
String formatEgp(int piastres) {
  final egp = piastres / 100.0;
  return '${egp.toStringAsFixed(egp.truncateToDouble() == egp ? 0 : 2)} ج.م';
}

int egpToPiastres(num egp) => (egp * 100).round();
