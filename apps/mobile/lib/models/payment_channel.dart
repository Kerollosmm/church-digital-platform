enum PaymentChannel {
  vodafoneCash('VODAFONE_CASH'),
  instaPay('INSTAPAY'),
  cash('CASH');

  final String value;
  const PaymentChannel(this.value);

  static PaymentChannel fromString(String str) {
    switch (str.toUpperCase()) {
      case 'VODAFONE_CASH':
        return PaymentChannel.vodafoneCash;
      case 'INSTAPAY':
        return PaymentChannel.instaPay;
      case 'CASH':
        return PaymentChannel.cash;
      default:
        throw ArgumentError('Unknown payment channel: $str');
    }
  }
}
