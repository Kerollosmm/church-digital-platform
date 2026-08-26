class EventBookingAdminItem {
  const EventBookingAdminItem({
    required this.id,
    required this.customerId,
    this.customerName,
    this.customerPhone,
    required this.eventTypeId,
    required this.eventTypeName,
    this.assignedVenueId,
    this.venueName,
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
  final String? customerName;
  final String? customerPhone;
  final String eventTypeId;
  final String eventTypeName;
  final String? assignedVenueId;
  final String? venueName;
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

  int get totalPriceEgp => totalPricePiastres ~/ 100;
  int get paidAmountEgp => paidAmountPiastres ~/ 100;
  int get remainingAmountEgp =>
      (totalPricePiastres - paidAmountPiastres) ~/ 100;

  factory EventBookingAdminItem.fromJson(
    Map<String, dynamic> json,
  ) => EventBookingAdminItem(
    id: json['id'] as String? ?? '',
    customerId: json['customer_id'] as String? ?? '',
    customerName: json['users']?['name'] as String?,
    customerPhone: json['users']?['phone'] as String?,
    eventTypeId: json['event_type_id'] as String? ?? '',
    eventTypeName:
        (json['event_types']?['name_ar'] ?? json['event_type_name'] ?? '')
            as String,
    assignedVenueId: json['assigned_venue_id'] as String?,
    venueName:
        (json['venues_resources']?['name_ar'] ?? json['venue_name']) as String?,
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

class VenueResourceItem {
  const VenueResourceItem({
    required this.id,
    required this.nameAr,
    this.locationDetailsAr,
    this.isActive = true,
  });

  final String id;
  final String nameAr;
  final String? locationDetailsAr;
  final bool isActive;

  factory VenueResourceItem.fromJson(Map<String, dynamic> json) =>
      VenueResourceItem(
        id: json['id'] as String? ?? '',
        nameAr: json['name_ar'] as String? ?? '',
        locationDetailsAr: json['location_details_ar'] as String?,
        isActive: json['is_active'] as bool? ?? true,
      );
}
