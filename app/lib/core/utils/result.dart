/// Minimal success/failure wrapper used across the analysis pipeline so
/// failures (bad image, no seeds found, corrupt model) are explicit return
/// values instead of exceptions crossing layer boundaries.
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;
  const factory Result.err(String message, [Object? cause]) = Err<T>;

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  R when<R>({
    required R Function(T value) ok,
    required R Function(String message, Object? cause) err,
  }) {
    final self = this;
    if (self is Ok<T>) return ok(self.value);
    if (self is Err<T>) return err(self.message, self.cause);
    throw StateError('unreachable');
  }

  T? get valueOrNull => this is Ok<T> ? (this as Ok<T>).value : null;
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

final class Err<T> extends Result<T> {
  final String message;
  final Object? cause;
  const Err(this.message, [this.cause]);
}
