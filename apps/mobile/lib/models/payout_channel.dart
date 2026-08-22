import 'payment_channel.dart';

class PayoutChannel {
  final int id;
  final PaymentChannel channel;
  final String displayNameAr;
  final String accountNumber;
  final String holderName;

  const PayoutChannel({
    required this.id,
    required this.channel,
    required this.displayNameAr,
    required this.accountNumber,
    required this.holderName,
  });

  factory PayoutChannel.fromJson(Map<String, dynamic> json) {
    return PayoutChannel(
      id: json['id'] as int,
      channel: PaymentChannel.fromString(json['channel'] as String),
      displayNameAr: json['display_name_ar'] as String,
      accountNumber: json['account_number'] as String,
      holderName: json['holder_name'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'channel': channel.value,
    'display_name_ar': displayNameAr,
    'account_number': accountNumber,
    'holder_name': holderName,
  };
}
