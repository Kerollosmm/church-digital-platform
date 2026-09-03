class EventBookingAdminItem {
  const EventBookingAdminItem({
    required this.id,
    required this.customerId,
    this.customerName,
    this.customerPhone,
    required this.eventTypeId,
    required this.eventTypeName,
    this.category = 'SACRAMENT',
    this.requiredDocumentsAr = const [],
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
  final String? customerName;
  final String? customerPhone;
  final String eventTypeId;
  final String eventTypeName;
  final String category;
  final List<String> requiredDocumentsAr;
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

  bool get isSacrament => category == 'SACRAMENT';
  bool get isActivity => category == 'ACTIVITY';

  double get totalPriceEgp => totalPricePiastres / 100.0;
  double get paidAmountEgp => paidAmountPiastres / 100.0;
  double get remainingAmountEgp =>
      (totalPricePiastres - paidAmountPiastres) / 100.0;

  factory EventBookingAdminItem.fromJson(
    Map<String, dynamic> json,
  ) => EventBookingAdminItem(
    id: json['id'] as String? ?? '',
    customerId: json['customer_id'] as String? ?? '',
    customerName:
        (json['customer_name'] ?? json['users']?['name']) as String?,
    customerPhone:
        (json['customer_phone'] ?? json['users']?['phone']) as String?,
    eventTypeId: json['event_type_id'] as String? ?? '',
    eventTypeName:
        (json['event_type_name'] ?? json['event_types']?['name_ar'] ?? '')
            as String,
    category: (json['category'] ??
            json['event_types']?['category'] ??
            'SACRAMENT')
        as String,
    requiredDocumentsAr: (json['event_types']?['required_documents_ar']
                as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    assignedVenueId: json['assigned_venue_id'] as String?,
    venueName:
        (json['venue_name'] ?? json['venues_resources']?['name_ar']) as String?,
    assignedPriestId: (json['assigned_priest_id'] as num?)?.toInt(),
    priestName: (json['priest_name'] ?? json['priests']?['name']) as String?,
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

class PriestAdminItem {
  const PriestAdminItem({
    required this.id,
    required this.name,
    this.photoUrl,
    this.phone,
    this.rank = 'PRIEST',
    this.activeBookingsCount = 0,
  });

  final int id;
  final String name;
  final String? photoUrl;
  final String? phone;
  final String rank;
  final int activeBookingsCount;

  factory PriestAdminItem.fromJson(Map<String, dynamic> json) =>
      PriestAdminItem(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        photoUrl: json['photo_url'] as String?,
        phone: json['phone'] as String?,
        rank: json['rank'] as String? ?? 'PRIEST',
        activeBookingsCount:
            (json['active_bookings_count'] as num?)?.toInt() ?? 0,
      );
}

class PriestScheduleItem {
  const PriestScheduleItem({
    required this.id,
    required this.priestId,
    this.priestName,
    required this.scheduleRange,
    this.startsAt,
    this.endsAt,
    this.scheduleType = 'EVENT_BOOKING',
    this.bookingId,
    this.notes,
    this.createdAt,
  });

  final String id;
  final int priestId;
  final String? priestName;
  final String scheduleRange;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String scheduleType;
  final String? bookingId;
  final String? notes;
  final DateTime? createdAt;

  factory PriestScheduleItem.fromJson(Map<String, dynamic> json) {
    return PriestScheduleItem(
      id: json['id'] as String? ?? '',
      priestId: (json['priest_id'] as num?)?.toInt() ?? 0,
      priestName: (json['priests']?['name'] ?? json['priest_name']) as String?,
      scheduleRange: json['schedule_range'] as String? ?? '',
      startsAt: DateTime.tryParse(json['starts_at'] as String? ?? ''),
      endsAt: DateTime.tryParse(json['ends_at'] as String? ?? ''),
      scheduleType: json['schedule_type'] as String? ?? 'EVENT_BOOKING',
      bookingId: json['booking_id'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }
}
