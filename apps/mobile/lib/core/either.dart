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
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Left($value)';
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
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Right($value)';
}
