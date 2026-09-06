import 'payment_channel.dart';

class PaymentProof {
  final int id;
  final int bookingId;
  final int? paymentId;
  final PaymentChannel channel;
  final String senderPhone;
  final String referenceNumber;
  final int amountClaimed;
  final String? imagePath;
  final String status;
  final String? rejectReasonCode;
  final String? collectorNote;
  final DateTime? reviewedAt;
  final DateTime createdAt;

  const PaymentProof({
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
    this.reviewedAt,
    required this.createdAt,
  });

  factory PaymentProof.fromJson(Map<String, dynamic> json) {
    return PaymentProof(
      id: json['id'] as int,
      bookingId: json['booking_id'] as int,
      paymentId: json['payment_id'] as int?,
      channel: PaymentChannel.fromString(json['channel'] as String),
      senderPhone: json['sender_phone'] as String,
      referenceNumber: json['reference_number'] as String,
      amountClaimed: json['amount_claimed'] as int,
      imagePath: json['image_path'] as String?,
      status: json['status'] as String,
      rejectReasonCode: json['reject_reason_code'] as String?,
      collectorNote: json['collector_note'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
