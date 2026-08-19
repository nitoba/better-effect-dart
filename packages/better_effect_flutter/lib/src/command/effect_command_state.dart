part of '../../better_effect_flutter.dart';

/// The observable UI state of an [EffectCommandBase].
///
/// The hierarchy is sealed so Views can render every state with exhaustive
/// switch patterns instead of coordinating unrelated loading/error booleans.
sealed class EffectCommandState<A extends Object, E extends Object> {
  const EffectCommandState._({
    required this.revision,
    required this.executionId,
  });

  /// Monotonically increasing visible-state revision.
  ///
  /// [EffectCommandListener] consumes revisions once, so navigation, dialogs,
  /// and SnackBars do not require `clearError()` or `clearResult()` calls.
  final int revision;

  /// Identifies the execution that produced this state.
  ///
  /// The initial/reset idle state uses `0`.
  final int executionId;

  /// The latest successful value visible from this state, when available.
  A? get dataOrNull => switch (this) {
    EffectCommandIdle<A, E>(:final previous) => previous,
    EffectCommandRunning<A, E>(:final previous) => previous,
    EffectCommandSuccess<A, E>(:final value) => value,
    EffectCommandFailure<A, E>(:final previous) => previous,
    EffectCommandDefect<A, E>(:final previous) => previous,
    EffectCommandInterrupted<A, E>(:final previous) => previous,
  };

  /// Previous successful data retained by this state, when available.
  A? get previousOrNull => switch (this) {
    EffectCommandSuccess<A, E>() => null,
    _ => dataOrNull,
  };

  /// The expected, typed failure visible from this state, when available.
  E? get errorOrNull => switch (this) {
    EffectCommandFailure<A, E>(:final error) => error,
    _ => null,
  };

  /// The unexpected defect visible from this state, when available.
  Object? get defectOrNull => switch (this) {
    EffectCommandDefect<A, E>(:final defect) => defect,
    _ => null,
  };

  /// The defect stack trace visible from this state, when available.
  StackTrace? get defectStackTraceOrNull => switch (this) {
    EffectCommandDefect<A, E>(:final stackTrace) => stackTrace,
    _ => null,
  };

  bool get isIdle => this is EffectCommandIdle<A, E>;

  bool get isRunning => this is EffectCommandRunning<A, E>;

  bool get isSuccess => this is EffectCommandSuccess<A, E>;

  bool get isFailure => this is EffectCommandFailure<A, E>;

  bool get isDefect => this is EffectCommandDefect<A, E>;

  bool get isInterrupted => this is EffectCommandInterrupted<A, E>;

  bool get isTerminal => isSuccess || isFailure || isDefect || isInterrupted;
}

/// The command has not started, or has been reset.
final class EffectCommandIdle<A extends Object, E extends Object>
    extends EffectCommandState<A, E> {
  const EffectCommandIdle._({
    required int revision,
    required int executionId,
    required this.previous,
  }) : super._(revision: revision, executionId: executionId);

  /// A successful value retained when resetting without clearing data.
  final A? previous;

  @override
  String toString() =>
      'EffectCommandIdle(revision: $revision, previous: $previous)';
}

/// The command is executing an Effect.
final class EffectCommandRunning<A extends Object, E extends Object>
    extends EffectCommandState<A, E> {
  const EffectCommandRunning._({
    required int revision,
    required int executionId,
    required this.startedAt,
    required this.previous,
  }) : super._(revision: revision, executionId: executionId);

  /// Time at which this execution became authoritative.
  final DateTime startedAt;

  /// Previous successful data when `keepPreviousData` is enabled.
  final A? previous;

  @override
  String toString() =>
      'EffectCommandRunning(executionId: $executionId, previous: $previous)';
}

/// The Effect completed successfully.
final class EffectCommandSuccess<A extends Object, E extends Object>
    extends EffectCommandState<A, E> {
  const EffectCommandSuccess._({
    required int revision,
    required int executionId,
    required this.value,
    required this.completedAt,
  }) : super._(revision: revision, executionId: executionId);

  final A value;

  final DateTime completedAt;

  @override
  String toString() =>
      'EffectCommandSuccess(executionId: $executionId, value: $value)';
}

/// The Effect completed with an expected, typed failure.
final class EffectCommandFailure<A extends Object, E extends Object>
    extends EffectCommandState<A, E> {
  const EffectCommandFailure._({
    required int revision,
    required int executionId,
    required this.error,
    required this.completedAt,
    required this.previous,
  }) : super._(revision: revision, executionId: executionId);

  final E error;

  final DateTime completedAt;

  /// Previous successful data when `keepPreviousData` is enabled.
  final A? previous;

  @override
  String toString() =>
      'EffectCommandFailure('
      'executionId: $executionId, error: $error, previous: $previous)';
}

/// The Effect terminated because of an unexpected defect.
final class EffectCommandDefect<A extends Object, E extends Object>
    extends EffectCommandState<A, E> {
  const EffectCommandDefect._({
    required int revision,
    required int executionId,
    required this.defect,
    required this.stackTrace,
    required this.completedAt,
    required this.previous,
  }) : super._(revision: revision, executionId: executionId);

  final Object defect;

  final StackTrace stackTrace;

  final DateTime completedAt;

  /// Previous successful data when `keepPreviousData` is enabled.
  final A? previous;

  @override
  String toString() =>
      'EffectCommandDefect('
      'executionId: $executionId, defect: $defect, previous: $previous)';
}

/// The command stopped owning an active execution result.
///
/// Ordinary Dart Futures are not generally cancellable. The underlying work
/// can continue, but its eventual completion is ignored by this command.
final class EffectCommandInterrupted<A extends Object, E extends Object>
    extends EffectCommandState<A, E> {
  const EffectCommandInterrupted._({
    required int revision,
    required int executionId,
    required this.interruptedAt,
    required this.previous,
  }) : super._(revision: revision, executionId: executionId);

  final DateTime interruptedAt;

  /// Previous successful data when `keepPreviousData` is enabled.
  final A? previous;

  @override
  String toString() =>
      'EffectCommandInterrupted('
      'executionId: $executionId, previous: $previous)';
}
