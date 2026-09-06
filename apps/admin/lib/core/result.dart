import 'package:supabase_flutter/supabase_flutter.dart';

/// Typed success/failure seam for admin repositories (mirrors mobile's
/// core/either.dart + core/failure.dart so both apps speak the same shape).
sealed class Either<L, R> {
  const Either();

  bool get isLeft => this is Left<L, R>;
  bool get isRight => this is Right<L, R>;

  T fold<T>(T Function(L left) onLeft, T Function(R right) onRight) =>
      switch (this) {
        Left(:final value) => onLeft(value),
        Right(:final value) => onRight(value),
      };

  L? get leftOrNull => fold((l) => l, (_) => null);
  R? get rightOrNull => fold((_) => null, (r) => r);
}

class Left<L, R> extends Either<L, R> {
  final L value;
  const Left(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Left<L, R> &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => Object.hash(runtimeType, value);
}

class Right<L, R> extends Either<L, R> {
  final R value;
  const Right(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Right<L, R> &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => Object.hash(runtimeType, value);
}

class Failure {
  final String code;
  final String message;
  const Failure({required this.code, this.message = ''});

  factory Failure.from(Object error) {
    if (error is PostgrestException) {
      if (error.code == '42501' || error.message == 'FORBIDDEN') {
        return const Failure(
          code: 'FORBIDDEN',
          message: 'ليس لديك صلاحية لتنفيذ هذا الإجراء',
        );
      }
      if (error.code == '28000' || error.message == 'UNAUTHORIZED') {
        return const Failure(
          code: 'UNAUTHORIZED',
          message: 'يرجى تسجيل الدخول أولاً',
        );
      }
      if (error.code == 'P0001') {
        return Failure(
          code: 'BAD_REQUEST',
          message: error.message.isNotEmpty ? error.message : 'بيانات غير صالحة',
        );
      }
      return Failure(
        code: error.code ?? 'INTERNAL',
        message: error.message.isNotEmpty
            ? error.message
            : 'حدث خطأ في الاتصال بالخادم',
      );
    }
    return const Failure(
      code: 'INTERNAL',
      message: 'حدث خطأ غير متوقع، يرجى المحاولة لاحقاً',
    );
  }

  @override
  String toString() => 'Failure($code: $message)';
}

/// Preserves legacy "loader throws" behavior at FutureBuilder seams while
/// repositories speak Either internally.
R unwrapOrThrow<R>(Either<Failure, R> e) => e.fold((l) => throw l, (r) => r);
