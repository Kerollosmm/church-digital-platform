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
    slotId: (json['slot_id'] as num?)?.toInt() ?? 0,
    serviceId: (json['service_id'] as num?)?.toInt() ?? 0,
    titleAr: json['title_ar'] as String? ?? '',
    startsAt: json['starts_at'] as String? ?? '',
    price: (json['price'] as num?)?.toInt() ?? 0,
    slotStatus: json['slot_status'] as String? ?? '',
    availableSeats: (json['available_seats'] as num?)?.toInt() ?? 0,
  );
}
