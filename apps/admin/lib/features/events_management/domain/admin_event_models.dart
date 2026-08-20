class AdminEventBookingModel {
  final int id;
  final String status;
  final String? userName;
  final String? userPhone;
  final int totalPricePiastres;
  final int paidAmountPiastres;
  final String? notes;
  final DateTime createdAt;

  const AdminEventBookingModel({
    required this.id,
    required this.status,
    this.userName,
    this.userPhone,
    required this.totalPricePiastres,
    required this.paidAmountPiastres,
    this.notes,
    required this.createdAt,
  });

  factory AdminEventBookingModel.fromJson(Map<String, dynamic> json) {
    final userMap = json['users'] as Map<String, dynamic>?;
    return AdminEventBookingModel(
      id: (json['id'] as num).toInt(),
      status: json['status'] as String? ?? 'SUBMITTED',
      userName: userMap?['full_name'] as String? ?? 'مواطن',
      userPhone: userMap?['phone'] as String?,
      totalPricePiastres: (json['total_price_piastres'] as num?)?.toInt() ??
                         ((json['total_amount'] as num?)?.toInt() ?? 0) * 100,
      paidAmountPiastres: (json['paid_amount_piastres'] as num?)?.toInt() ??
                         ((json['paid_amount'] as num?)?.toInt() ?? 0) * 100,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  double get totalPriceEgp => totalPricePiastres / 100.0;
  double get paidAmountEgp => paidAmountPiastres / 100.0;
  double get remainingEgp => (totalPricePiastres - paidAmountPiastres) / 100.0;
}

class VenueResourceModel {
  final int id;
  final String nameAr;
  final int capacity;
  final bool isActive;

  const VenueResourceModel({
    required this.id,
    required this.nameAr,
    required this.capacity,
    this.isActive = true,
  });

  factory VenueResourceModel.fromJson(Map<String, dynamic> json) {
    return VenueResourceModel(
      id: (json['id'] as num).toInt(),
      nameAr: json['name_ar'] as String? ?? 'قاعة المناسبات',
      capacity: (json['capacity'] as num?)?.toInt() ?? 100,
      isActive: json['is_active'] as bool? ?? json['active'] as bool? ?? true,
    );
  }
}
