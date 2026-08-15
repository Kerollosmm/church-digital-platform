abstract class Failure {
  final String message;
  final String? code;
  final Object? originalError;

  const Failure(this.message, {this.code, this.originalError});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          code == other.code;

  @override
  int get hashCode => Object.hash(message, code);

  @override
  String toString() => '$runtimeType(message: $message, code: $code)';
}

class BookingFailure extends Failure {
  const BookingFailure(super.message, {super.code, super.originalError});
}

class CheckoutFailure extends Failure {
  final int? bookingId;
  const CheckoutFailure(
    super.message, {
    this.bookingId,
    super.code,
    super.originalError,
  });
}

class AuthFailure extends Failure {
  const AuthFailure(super.message, {super.code, super.originalError});
}

class ServerFailure extends Failure {
  const ServerFailure(super.message, {super.code, super.originalError});
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.code, super.originalError});
}
