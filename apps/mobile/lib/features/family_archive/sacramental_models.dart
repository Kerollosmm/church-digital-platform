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
  final DateTime sacramentDate;
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
  final DateTime issuedAt;

  const SacramentalRecord({
    required this.id,
    required this.sacramentType,
    required this.recipientNameAr,
    this.recipientNationalId,
    required this.sacramentDate,
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
    required this.issuedAt,
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
      sacramentDate: json['sacrament_date'] != null
          ? DateTime.tryParse(json['sacrament_date'].toString()) ??
                DateTime.now()
          : DateTime.now(),
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
      issuedAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class CertificateVerificationResult {
  final bool isValid;
  final bool isRevoked;
  final String? recordId;
  final SacramentType? sacramentType;
  final String? recipientNameAr;
  final DateTime? sacramentDate;
  final String? officiatingPriestName;
  final String? churchLocationAr;
  final String? status;
  final String? revocationReason;
  final DateTime? issuedAt;
  final String? errorMessageAr;

  const CertificateVerificationResult({
    required this.isValid,
    this.isRevoked = false,
    this.recordId,
    this.sacramentType,
    this.recipientNameAr,
    this.sacramentDate,
    this.officiatingPriestName,
    this.churchLocationAr,
    this.status,
    this.revocationReason,
    this.issuedAt,
    this.errorMessageAr,
  });

  factory CertificateVerificationResult.fromJson(Map<String, dynamic> json) {
    final isValid = json['is_valid'] as bool? ?? false;
    final isRevoked = json['status'] == 'REVOKED' || json['is_revoked'] == true;
    return CertificateVerificationResult(
      isValid: isValid,
      isRevoked: isRevoked,
      recordId: json['record_id'] as String?,
      sacramentType: json['sacrament_type'] != null
          ? SacramentType.fromString(json['sacrament_type'] as String?)
          : null,
      recipientNameAr: json['recipient_name_ar'] as String?,
      sacramentDate: json['sacrament_date'] != null
          ? DateTime.tryParse(json['sacrament_date'].toString())
          : null,
      officiatingPriestName: json['officiating_priest_name'] as String?,
      churchLocationAr: json['church_location_ar'] as String?,
      status: json['status'] as String?,
      revocationReason: json['revocation_reason'] as String?,
      issuedAt: json['issued_at'] != null
          ? DateTime.tryParse(json['issued_at'].toString())
          : null,
      errorMessageAr: json['message_ar'] as String?,
    );
  }
}
