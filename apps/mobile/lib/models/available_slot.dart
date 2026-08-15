class AvailableSlot {
  const AvailableSlot({
    required this.slotId,
    required this.serviceId,
    required this.titleAr,
    required this.startsAt,
    required this.price,
    required this.slotStatus,
    this.availableSeats = 0,
  });

  final int slotId;
  final int serviceId;
  final String titleAr;
  final String startsAt;
  final int price;
  final String slotStatus;
  final int availableSeats;

  factory AvailableSlot.fromJson(Map<String, dynamic> json) => AvailableSlot(
    slotId: json['slot_id'] as int,
    serviceId: json['service_id'] as int,
    titleAr: json['title_ar'] as String,
    startsAt: json['starts_at'] as String,
    price: (json['price'] ?? 0) as int,
    slotStatus: json['slot_status'] as String,
    availableSeats: (json['available_seats'] ?? 0) as int,
  );
}
