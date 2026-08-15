enum BookingStatus {
  pendingPayment('PENDING_PAYMENT'),
  awaitingCall('AWAITING_CALL'),
  confirmed('CONFIRMED'),
  completed('COMPLETED'),
  cancelled('CANCELLED'),
  rescheduled('RESCHEDULED');

  const BookingStatus(this.db);
  final String db;

  static BookingStatus fromDb(String value) => values.firstWhere(
    (s) => s.db == value,
    orElse: () => BookingStatus.cancelled,
  );
}
