enum SacramentType {
  baptism('BAPTISM', 'سر المعمودية'),
  marriage('MARRIAGE', 'سر الزيجة / الإكليل'),
  deaconOrdination('DEACON_ORDINATION', 'رسامة الشمامسة'),
  communion('COMMUNION', 'سر التناول / التثبيت');

  const SacramentType(this.value, this.labelAr);
  final String value;
  final String labelAr;

  static SacramentType fromString(String? val) {
    return SacramentType.values.firstWhere(
      (e) => e.value == val,
      orElse: () => SacramentType.baptism,
    );
  }
}

class SacramentalRecord {
  final String id;
  final SacramentType sacramentType;
  final String recipientNameAr;
  final String? recipientNationalId;
  final String? recipientUserId;
  final DateTime sacramentDate;
  final int? officiatingPriestId;
  final String? officiatingPriestName;
  final String churchLocationAr;
  final String? registryBookNumber;
  final String? registryPageNumber;
  final String? registryEntryNumber;
  final String? godparentsAr;
  final String verificationToken;
  final String status;
  final String? revocationReason;
  final String? pdfStoragePath;
  final String? notes;
  final DateTime createdAt;
  final String? createdBy;

  const SacramentalRecord({
    required this.id,
    required this.sacramentType,
    required this.recipientNameAr,
    this.recipientNationalId,
    this.recipientUserId,
    required this.sacramentDate,
    this.officiatingPriestId,
    this.officiatingPriestName,
    required this.churchLocationAr,
    this.registryBookNumber,
    this.registryPageNumber,
    this.registryEntryNumber,
    this.godparentsAr,
    required this.verificationToken,
    required this.status,
    this.revocationReason,
    this.pdfStoragePath,
    this.notes,
    required this.createdAt,
    this.createdBy,
  });

  bool get isRevoked => status == 'REVOKED';

  factory SacramentalRecord.fromJson(Map<String, dynamic> json) {
    return SacramentalRecord(
      id: json['id'] as String? ?? '',
      sacramentType: SacramentType.fromString(
        json['sacrament_type'] as String?,
      ),
      recipientNameAr: json['recipient_name_ar'] as String? ?? '',
      recipientNationalId: json['recipient_national_id'] as String?,
      recipientUserId: json['recipient_user_id'] as String?,
      sacramentDate: json['sacrament_date'] != null
          ? DateTime.tryParse(json['sacrament_date'].toString()) ??
                DateTime.now()
          : DateTime.now(),
      officiatingPriestId: json['officiating_priest_id'] != null
          ? int.tryParse(json['officiating_priest_id'].toString())
          : null,
      officiatingPriestName: json['priests'] is Map
          ? (json['priests']['name'] as String?)
          : (json['officiating_priest_name'] as String?),
      churchLocationAr:
          json['church_location_ar'] as String? ??
          'كنيسة السيدة العذراء والأنبا بيشوي',
      registryBookNumber: json['registry_book_number'] as String?,
      registryPageNumber: json['registry_page_number'] as String?,
      registryEntryNumber: json['registry_entry_number'] as String?,
      godparentsAr: json['godparents_ar'] as String?,
      verificationToken: json['verification_token'] as String? ?? '',
      status: json['status'] as String? ?? 'ACTIVE',
      revocationReason: json['revocation_reason'] as String?,
      pdfStoragePath: json['pdf_storage_path'] as String?,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      createdBy: json['created_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sacrament_type': sacramentType.value,
    'recipient_name_ar': recipientNameAr,
    'recipient_national_id': recipientNationalId,
    'recipient_user_id': recipientUserId,
    'sacrament_date': sacramentDate.toIso8601String().split('T').first,
    'officiating_priest_id': officiatingPriestId,
    'church_location_ar': churchLocationAr,
    'registry_book_number': registryBookNumber,
    'registry_page_number': registryPageNumber,
    'registry_entry_number': registryEntryNumber,
    'godparents_ar': godparentsAr,
    'verification_token': verificationToken,
    'status': status,
    'revocation_reason': revocationReason,
    'pdf_storage_path': pdfStoragePath,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'created_by': createdBy,
  };
}

class IssueSacramentInput {
  final SacramentType sacramentType;
  final String recipientNameAr;
  final DateTime sacramentDate;
  final String churchLocationAr;
  final String? recipientNationalId;
  final String? recipientUserId;
  final int? officiatingPriestId;
  final String? registryBookNumber;
  final String? registryPageNumber;
  final String? registryEntryNumber;
  final String? godparentsAr;
  final String? pdfStoragePath;
  final String? notes;

  const IssueSacramentInput({
    required this.sacramentType,
    required this.recipientNameAr,
    required this.sacramentDate,
    this.churchLocationAr = 'كنيسة السيدة العذراء والأنبا بيشوي',
    this.recipientNationalId,
    this.recipientUserId,
    this.officiatingPriestId,
    this.registryBookNumber,
    this.registryPageNumber,
    this.registryEntryNumber,
    this.godparentsAr,
    this.pdfStoragePath,
    this.notes,
  });

  Map<String, dynamic> toRpcParams() => {
    'p_sacrament_type': sacramentType.value,
    'p_recipient_name_ar': recipientNameAr.trim(),
    'p_sacrament_date': sacramentDate.toIso8601String().split('T').first,
    'p_church_location_ar': churchLocationAr.trim(),
    'p_recipient_national_id': recipientNationalId?.trim().isEmpty ?? true
        ? null
        : recipientNationalId?.trim(),
    'p_recipient_user_id': recipientUserId?.trim().isEmpty ?? true
        ? null
        : recipientUserId?.trim(),
    'p_officiating_priest_id': officiatingPriestId,
    'p_registry_book_number': registryBookNumber?.trim().isEmpty ?? true
        ? null
        : registryBookNumber?.trim(),
    'p_registry_page_number': registryPageNumber?.trim().isEmpty ?? true
        ? null
        : registryPageNumber?.trim(),
    'p_registry_entry_number': registryEntryNumber?.trim().isEmpty ?? true
        ? null
        : registryEntryNumber?.trim(),
    'p_godparents_ar': godparentsAr?.trim().isEmpty ?? true
        ? null
        : godparentsAr?.trim(),
    'p_pdf_storage_path': pdfStoragePath?.trim().isEmpty ?? true
        ? null
        : pdfStoragePath?.trim(),
    'p_notes': notes?.trim().isEmpty ?? true ? null : notes?.trim(),
  };
}
