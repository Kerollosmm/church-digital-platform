class Booking {
  const Booking({
    required this.id,
    required this.status,
    this.serviceName = '',
    this.paidAmount = 0,
    this.createdAt,
  });

  final int id;
  final String status;
  final String serviceName;
  final int paidAmount;
  final DateTime? createdAt;

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
    id: (json['id'] as num?)?.toInt() ?? 0,
    status: json['status'] as String? ?? '',
    serviceName: (json['service_name'] ?? json['title_ar'] ?? '') as String,
    paidAmount: (json['paid_amount'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status,
    'service_name': serviceName,
    'paid_amount': paidAmount,
    'created_at': createdAt?.toIso8601String(),
  };
}
