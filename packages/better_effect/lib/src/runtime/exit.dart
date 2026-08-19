part of '../../better_effect.dart';

/// The complete outcome of running an [Effect].
///
/// Expected failures are represented by [ExitFailure]. Unhandled exceptions,
/// programming errors, and dependency-resolution failures are represented by
/// [ExitDefect].
sealed class Exit<A extends Object, E extends Object> {
  const Exit();

  bool get isSuccess => this is ExitSuccess<A, E>;

  bool get isFailure => this is ExitFailure<A, E>;

  bool get isDefect => this is ExitDefect<A, E>;

  bool get isInterrupted => this is ExitInterrupted<A, E>;
}

/// An Effect completed successfully.
final class ExitSuccess<A extends Object, E extends Object> extends Exit<A, E> {
  const ExitSuccess(this.value);

  final A value;

  @override
  String toString() => 'ExitSuccess($value)';
}

/// An Effect completed with an expected, typed failure.
final class ExitFailure<A extends Object, E extends Object> extends Exit<A, E> {
  const ExitFailure(this.error);

  final E error;

  @override
  String toString() => 'ExitFailure($error)';
}

/// An Effect terminated because of an unexpected defect.
final class ExitDefect<A extends Object, E extends Object> extends Exit<A, E> {
  const ExitDefect(this.defect, this.stackTrace);

  final Object defect;
  final StackTrace stackTrace;

  @override
  String toString() => 'ExitDefect($defect)';
}

/// Execution or runtime ownership ended without a success or typed failure.
final class ExitInterrupted<A extends Object, E extends Object>
    extends Exit<A, E> {
  const ExitInterrupted();

  @override
  String toString() => 'ExitInterrupted()';
}

ResultDart<A, E> _resultFromExit<A extends Object, E extends Object>(
  Exit<A, E> exit,
) {
  if (exit is ExitSuccess<A, E>) {
    return Success<A, E>(exit.value);
  }

  if (exit is ExitFailure<A, E>) {
    return Failure<A, E>(exit.error);
  }

  if (exit is ExitDefect<A, E>) {
    Error.throwWithStackTrace(exit.defect, exit.stackTrace);
  }

  throw StateError('An interrupted Effect does not have a Result value.');
}
