abstract class Failure {
  final String message;
  final String? code;
  final Object? originalError;

  const Failure(this.message, {this.code, this.originalError});

  factory Failure.fromError(Object error) {
    final errStr = error.toString();
    if (errStr.contains('42501') || errStr.contains('FORBIDDEN')) {
      return AuthFailure(
        'ليس لديك صلاحية لتنفيذ هذا الإجراء',
        code: 'FORBIDDEN',
        originalError: error,
      );
    }
    if (errStr.contains('28000') || errStr.contains('UNAUTHORIZED')) {
      return AuthFailure(
        'يرجى تسجيل الدخول أولاً',
        code: 'UNAUTHORIZED',
        originalError: error,
      );
    }
    if (errStr.contains('P0001') || errStr.contains('BAD_REQUEST')) {
      return BookingFailure(
        'بيانات غير صالحة أو غير مكتملة',
        code: 'BAD_REQUEST',
        originalError: error,
      );
    }
    return ServerFailure(
      'حدث خطأ في الاتصال بالخادم، يرجى المحاولة لاحقاً',
      code: 'INTERNAL',
      originalError: error,
    );
  }

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
