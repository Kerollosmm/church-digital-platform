import 'payment_channel.dart';

class PaymentProofInput {
  final int bookingId;
  final PaymentChannel channel;
  final String senderPhone;
  final String referenceNumber;
  final int amount;
  final String? imagePath;

  const PaymentProofInput({
    required this.bookingId,
    required this.channel,
    required this.senderPhone,
    required this.referenceNumber,
    required this.amount,
    this.imagePath,
  });

  Map<String, dynamic> toRpcParams() {
    return {
      'p_booking_id': bookingId,
      'p_channel': channel.value,
      'p_sender_phone': senderPhone,
      'p_reference': referenceNumber,
      'p_amount': amount,
      'p_image_path': imagePath,
    };
  }
}
