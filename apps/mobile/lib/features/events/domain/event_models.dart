class EventTypeModel {
  final int id;
  final String nameAr;
  final String? descriptionAr;
  final int basePricePiastres;
  final bool isActive;

  const EventTypeModel({
    required this.id,
    required this.nameAr,
    this.descriptionAr,
    required this.basePricePiastres,
    this.isActive = true,
  });

  factory EventTypeModel.fromJson(Map<String, dynamic> json) {
    return EventTypeModel(
      id: (json['id'] as num).toInt(),
      nameAr: json['name_ar'] as String? ?? json['title_ar'] as String? ?? 'مناسبة كنسية',
      descriptionAr: json['description_ar'] as String?,
      basePricePiastres: (json['base_price_piastres'] as num?)?.toInt() ??
                         ((json['base_price'] as num?)?.toInt() ?? 0) * 100,
      isActive: json['is_active'] as bool? ?? json['active'] as bool? ?? true,
    );
  }

  double get basePriceEgp => basePricePiastres / 100.0;
}

class ExtraServiceModel {
  final int id;
  final String nameAr;
  final String? descriptionAr;
  final int unitPricePiastres;
  final bool isQuantityBased;
  final bool isActive;

  const ExtraServiceModel({
    required this.id,
    required this.nameAr,
    this.descriptionAr,
    required this.unitPricePiastres,
    this.isQuantityBased = false,
    this.isActive = true,
  });

  factory ExtraServiceModel.fromJson(Map<String, dynamic> json) {
    return ExtraServiceModel(
      id: (json['id'] as num).toInt(),
      nameAr: json['name_ar'] as String? ?? json['title_ar'] as String? ?? 'خدمة إضافية',
      descriptionAr: json['description_ar'] as String?,
      unitPricePiastres: (json['unit_price_piastres'] as num?)?.toInt() ??
                         ((json['unit_price'] as num?)?.toInt() ?? 0) * 100,
      isQuantityBased: json['is_quantity_based'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? json['active'] as bool? ?? true,
    );
  }

  double get unitPriceEgp => unitPricePiastres / 100.0;
}

class SelectedExtraService {
  final ExtraServiceModel service;
  final int quantity;

  const SelectedExtraService({
    required this.service,
    required this.quantity,
  });

  int get totalPricePiastres => service.unitPricePiastres * quantity;
  double get totalPriceEgp => totalPricePiastres / 100.0;
}

class EventBookingModel {
  final int id;
  final String status;
  final int totalPricePiastres;
  final int paidAmountPiastres;
  final String? notes;
  final DateTime createdAt;

  const EventBookingModel({
    required this.id,
    required this.status,
    required this.totalPricePiastres,
    required this.paidAmountPiastres,
    this.notes,
    required this.createdAt,
  });

  factory EventBookingModel.fromJson(Map<String, dynamic> json) {
    return EventBookingModel(
      id: (json['id'] as num).toInt(),
      status: json['status'] as String? ?? 'SUBMITTED',
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
