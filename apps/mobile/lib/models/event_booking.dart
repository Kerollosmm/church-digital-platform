class EventType {
  const EventType({
    required this.id,
    required this.nameAr,
    this.descriptionAr,
    required this.basePricePiastres,
    required this.defaultDurationMinutes,
    this.isActive = true,
  });

  final String id;
  final String nameAr;
  final String? descriptionAr;
  final int basePricePiastres;
  final int defaultDurationMinutes;
  final bool isActive;

  double get basePriceEgp => basePricePiastres / 100.0;

  factory EventType.fromJson(Map<String, dynamic> json) => EventType(
    id: json['id'] as String? ?? '',
    nameAr: json['name_ar'] as String? ?? '',
    descriptionAr: json['description_ar'] as String?,
    basePricePiastres: (json['base_price_piastres'] as num?)?.toInt() ?? 0,
    defaultDurationMinutes:
        (json['default_duration_minutes'] as num?)?.toInt() ?? 60,
    isActive: json['is_active'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name_ar': nameAr,
    'description_ar': descriptionAr,
    'base_price_piastres': basePricePiastres,
    'default_duration_minutes': defaultDurationMinutes,
    'is_active': isActive,
  };
}

class ExtraService {
  const ExtraService({
    required this.id,
    required this.nameAr,
    this.descriptionAr,
    required this.pricePiastres,
    this.isQuantityBased = false,
    this.maxQuantity = 1,
    this.isActive = true,
  });

  final String id;
  final String nameAr;
  final String? descriptionAr;
  final int pricePiastres;
  final bool isQuantityBased;
  final int maxQuantity;
  final bool isActive;

  double get priceEgp => pricePiastres / 100.0;

  factory ExtraService.fromJson(Map<String, dynamic> json) => ExtraService(
    id: json['id'] as String? ?? '',
    nameAr: json['name_ar'] as String? ?? '',
    descriptionAr: json['description_ar'] as String?,
    pricePiastres: (json['price_piastres'] as num?)?.toInt() ?? 0,
    isQuantityBased: json['is_quantity_based'] as bool? ?? false,
    maxQuantity: (json['max_quantity'] as num?)?.toInt() ?? 1,
    isActive: json['is_active'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name_ar': nameAr,
    'description_ar': descriptionAr,
    'price_piastres': pricePiastres,
    'is_quantity_based': isQuantityBased,
    'max_quantity': maxQuantity,
    'is_active': isActive,
  };
}

class EventBooking {
  const EventBooking({
    required this.id,
    required this.customerId,
    required this.eventTypeId,
    this.eventTypeName = '',
    this.assignedVenueId,
    this.venueName,
    this.assignedPriestId,
    this.priestName,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.notes,
    this.rejectionReason,
    this.basePricePiastres = 0,
    this.extraServicesPricePiastres = 0,
    this.totalPricePiastres = 0,
    this.paidAmountPiastres = 0,
    this.createdAt,
  });

  final String id;
  final String customerId;
  final String eventTypeId;
  final String eventTypeName;
  final String? assignedVenueId;
  final String? venueName;
  final int? assignedPriestId;
  final String? priestName;
  final DateTime startTime;
  final DateTime endTime;
  final String status;
  final String? notes;
  final String? rejectionReason;
  final int basePricePiastres;
  final int extraServicesPricePiastres;
  final int totalPricePiastres;
  final int paidAmountPiastres;
  final DateTime? createdAt;

  double get totalPriceEgp => totalPricePiastres / 100.0;
  double get paidAmountEgp => paidAmountPiastres / 100.0;
  double get remainingAmountEgp =>
      (totalPricePiastres - paidAmountPiastres) / 100.0;

  factory EventBooking.fromJson(Map<String, dynamic> json) => EventBooking(
    id: json['id'] as String? ?? '',
    customerId: json['customer_id'] as String? ?? '',
    eventTypeId: json['event_type_id'] as String? ?? '',
    eventTypeName:
        (json['event_types']?['name_ar'] ?? json['event_type_name'] ?? '')
            as String,
    assignedVenueId: json['assigned_venue_id'] as String?,
    venueName:
        (json['venues_resources']?['name_ar'] ?? json['venue_name']) as String?,
    assignedPriestId: (json['assigned_priest_id'] as num?)?.toInt(),
    priestName: (json['priests']?['name'] ?? json['priest_name']) as String?,
    startTime:
        DateTime.tryParse(json['start_time'] as String? ?? '') ??
        DateTime.now(),
    endTime:
        DateTime.tryParse(json['end_time'] as String? ?? '') ?? DateTime.now(),
    status: json['status'] as String? ?? 'SUBMITTED',
    notes: json['notes'] as String?,
    rejectionReason: json['rejection_reason'] as String?,
    basePricePiastres: (json['base_price_piastres'] as num?)?.toInt() ?? 0,
    extraServicesPricePiastres:
        (json['extra_services_price_piastres'] as num?)?.toInt() ?? 0,
    totalPricePiastres: (json['total_price_piastres'] as num?)?.toInt() ?? 0,
    paidAmountPiastres: (json['paid_amount_piastres'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
  );
}
