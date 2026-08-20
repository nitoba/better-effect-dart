part of '../../better_effect.dart';

/// Typed-failure retry for every [Effect].
extension EffectRetryOps<A extends Object, E extends Object> on Effect<A, E> {
  /// Re-run this lazy Effect according to [policy].
  ///
  /// The initial execution is attempt one and counts toward `maxAttempts` in
  /// the built-in policies. Only typed failures are eligible. Success stops,
  /// defects remain defects, and interruption stops at the next cooperative
  /// boundary.
  ///
  /// Every attempt owns a fresh child [Scope]. Attempt resources are released
  /// before policy evaluation, sleeping, or starting the next attempt.
  Effect<A, E> retry(
    RetryPolicy<E> policy, {
    bool Function(E error)? whileError,
  }) {
    return Effect<A, E>._(
      (context) => _runRetriedEffect<A, E>(
        source: this,
        policy: policy,
        whileError: whileError,
        context: context,
      ),
      _localBindings,
    );
  }
}

Future<ResultDart<A, E>> _runRetriedEffect<A extends Object, E extends Object>({
  required Effect<A, E> source,
  required RetryPolicy<E> policy,
  required bool Function(E error)? whileError,
  required _RuntimeContext context,
}) async {
  var attempt = 0;

  while (true) {
    context.cancellation.throwIfCancelled();
    attempt++;

    final attemptScope = context.scope._fork();
    final attemptContext = context._withScope(
      attemptScope,
      cancellation: context.cancellation,
      observation: context.observation,
    );

    late Exit<A, E> attemptOutcome;
    try {
      final result = await source._run(attemptContext);
      attemptOutcome = result.fold<Exit<A, E>>(
        (value) => ExitSuccess<A, E>(value),
        (error) => ExitFailure<A, E>(error),
      );
    } on _CancellationRequested {
      attemptOutcome = ExitInterrupted<A, E>();
    } catch (error, stackTrace) {
      attemptOutcome = ExitDefect<A, E>(error, stackTrace);
    }

    final closed = await context._closeNestedScope<A, E>(
      attemptScope,
      attemptOutcome,
    );
    final outcome = closed.outcome;

    if (outcome is ExitDefect<A, E>) {
      _emitRetryEvent<E>(
        context,
        attemptScope,
        policy,
        attempt: attempt,
        decision: RetryDecision.defect,
        defect: outcome.defect,
        stackTrace: outcome.stackTrace,
      );
      Error.throwWithStackTrace(outcome.defect, outcome.stackTrace);
    }

    if (outcome is ExitInterrupted<A, E> || context.cancellation.isCancelled) {
      _emitRetryEvent<E>(
        context,
        attemptScope,
        policy,
        attempt: attempt,
        decision: RetryDecision.interrupted,
      );
      throw const _CancellationRequested();
    }

    if (outcome is ExitSuccess<A, E>) {
      _emitRetryEvent<E>(
        context,
        attemptScope,
        policy,
        attempt: attempt,
        decision: RetryDecision.succeeded,
      );
      return Success<A, E>(outcome.value);
    }

    final failure = outcome as ExitFailure<A, E>;
    if (closed.cleanupFailed) {
      _emitRetryEvent<E>(
        context,
        attemptScope,
        policy,
        attempt: attempt,
        decision: RetryDecision.cleanupFailed,
        previousFailure: failure.error,
      );
      return Failure<A, E>(failure.error);
    }

    final filter = whileError;
    if (filter != null) {
      late final bool accepted;
      try {
        accepted = filter(failure.error);
      } catch (error, stackTrace) {
        _emitRetryEvent<E>(
          context,
          attemptScope,
          policy,
          attempt: attempt,
          decision: RetryDecision.defect,
          previousFailure: failure.error,
          defect: error,
          stackTrace: stackTrace,
        );
        Error.throwWithStackTrace(error, stackTrace);
      }

      if (!accepted) {
        _emitRetryEvent<E>(
          context,
          attemptScope,
          policy,
          attempt: attempt,
          decision: RetryDecision.failureRejected,
          previousFailure: failure.error,
        );
        return Failure<A, E>(failure.error);
      }
    }

    late final Duration? delay;
    try {
      delay = policy.nextDelay(
        RetryContext<E>(
          attempt: attempt,
          error: failure.error,
          nextRandom: () => context._resolve<EffectRandom>().nextDouble(),
        ),
      );
      if (delay != null && delay.isNegative) {
        throw ArgumentError.value(
          delay,
          'RetryPolicy.nextDelay',
          'must return null or a non-negative Duration',
        );
      }
    } catch (error, stackTrace) {
      _emitRetryEvent<E>(
        context,
        attemptScope,
        policy,
        attempt: attempt,
        decision: RetryDecision.defect,
        previousFailure: failure.error,
        defect: error,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }

    if (delay == null) {
      _emitRetryEvent<E>(
        context,
        attemptScope,
        policy,
        attempt: attempt,
        decision: RetryDecision.policyStopped,
        previousFailure: failure.error,
      );
      return Failure<A, E>(failure.error);
    }

    _emitRetryEvent<E>(
      context,
      attemptScope,
      policy,
      attempt: attempt,
      decision: RetryDecision.retryScheduled,
      previousFailure: failure.error,
      plannedDelay: delay,
    );

    try {
      if (delay == Duration.zero) {
        await Future<void>.value();
      } else {
        final clock = context._resolve<EffectClock>();
        await clock.sleep(delay, context.cancellation);
      }
      context.cancellation.throwIfCancelled();
    } on _CancellationRequested {
      _emitRetryEvent<E>(
        context,
        attemptScope,
        policy,
        attempt: attempt,
        decision: RetryDecision.interrupted,
        previousFailure: failure.error,
        plannedDelay: delay,
      );
      rethrow;
    } catch (error, stackTrace) {
      _emitRetryEvent<E>(
        context,
        attemptScope,
        policy,
        attempt: attempt,
        decision: RetryDecision.defect,
        previousFailure: failure.error,
        plannedDelay: delay,
        defect: error,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

void _emitRetryEvent<E extends Object>(
  _RuntimeContext context,
  Scope attemptScope,
  RetryPolicy<E> policy, {
  required int attempt,
  required RetryDecision decision,
  Object? previousFailure,
  Duration? plannedDelay,
  Object? defect,
  StackTrace? stackTrace,
}) {
  final observation = context.observation;
  if (observation == null) return;

  observation.observers.retry(
    RetryEvent(
      context: observation.context(attemptScope, context.locals),
      timestamp: DateTime.now(),
      attempt: attempt,
      policyType: policy.runtimeType,
      decision: decision,
      previousFailure: previousFailure,
      plannedDelay: plannedDelay,
      defect: defect,
      stackTrace: stackTrace,
    ),
  );
}
