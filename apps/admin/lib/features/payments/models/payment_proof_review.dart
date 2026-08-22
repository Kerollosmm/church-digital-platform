class PaymentProofReview {
  final int id;
  final int bookingId;
  final int? paymentId;
  final String channel;
  final String senderPhone;
  final String referenceNumber;
  final int amountClaimed;
  final String? imagePath;
  final String status;
  final String? rejectReasonCode;
  final String? collectorNote;
  final DateTime createdAt;

  const PaymentProofReview({
    required this.id,
    required this.bookingId,
    this.paymentId,
    required this.channel,
    required this.senderPhone,
    required this.referenceNumber,
    required this.amountClaimed,
    this.imagePath,
    required this.status,
    this.rejectReasonCode,
    this.collectorNote,
    required this.createdAt,
  });

  factory PaymentProofReview.fromJson(Map<String, dynamic> json) {
    return PaymentProofReview(
      id: (json['id'] as num).toInt(),
      bookingId: (json['booking_id'] as num).toInt(),
      paymentId: (json['payment_id'] as num?)?.toInt(),
      channel: json['channel'] as String? ?? 'VODAFONE_CASH',
      senderPhone: json['sender_phone'] as String? ?? '',
      referenceNumber: json['reference_number'] as String? ?? '',
      amountClaimed: (json['amount_claimed'] as num?)?.toInt() ?? 0,
      imagePath: json['image_path'] as String?,
      status: json['status'] as String? ?? 'PENDING',
      rejectReasonCode: json['reject_reason_code'] as String?,
      collectorNote: json['collector_note'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  String get channelDisplayName {
    switch (channel) {
      case 'VODAFONE_CASH':
        return 'فودافون كاش';
      case 'INSTAPAY':
        return 'إنستاباي';
      case 'CASH':
        return 'نقداً';
      default:
        return channel;
    }
  }
}
