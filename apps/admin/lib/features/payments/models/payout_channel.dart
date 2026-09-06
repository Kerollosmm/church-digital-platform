class PayoutChannel {
  final int? id;
  final String channel;
  final String displayNameAr;
  final String accountNumber;
  final String holderName;

  const PayoutChannel({
    this.id,
    required this.channel,
    required this.displayNameAr,
    required this.accountNumber,
    required this.holderName,
  });

  factory PayoutChannel.fromJson(Map<String, dynamic> json) {
    return PayoutChannel(
      id: (json['id'] as num?)?.toInt(),
      channel: json['channel'] as String? ?? '',
      displayNameAr: json['display_name_ar'] as String? ?? '',
      accountNumber: json['account_number'] as String? ?? '',
      holderName: json['holder_name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'channel': channel,
    'display_name_ar': displayNameAr,
    'account_number': accountNumber,
    'holder_name': holderName,
  };
}
