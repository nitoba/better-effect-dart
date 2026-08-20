part of '../../better_effect.dart';

/// Information available when a typed failure asks a [RetryPolicy] whether
/// another attempt should run.
///
/// [attempt] is the attempt that just failed and starts at one. Therefore a
/// policy with `maxAttempts: 3` may schedule work after failures from attempts
/// one and two, but returns null after attempt three.
final class RetryContext<E extends Object> {
  RetryContext({
    required this.attempt,
    required this.error,
    required double Function() nextRandom,
  }) : _nextRandom = nextRandom {
    if (attempt <= 0) {
      throw ArgumentError.value(attempt, 'attempt', 'must be positive');
    }
  }

  /// One-based number of the attempt that produced [error].
  final int attempt;

  /// Typed failure produced by the attempt.
  final E error;

  final double Function() _nextRandom;

  /// Obtain one uniform random value in `[0, 1)`.
  ///
  /// The underlying [EffectRandom] service is resolved lazily. Policies that do
  /// not call this method do not require randomness to be registered.
  double nextRandom() {
    final value = _nextRandom();
    if (!value.isFinite || value < 0 || value >= 1) {
      throw StateError(
        'EffectRandom.nextDouble() must return a finite value in [0, 1), '
        'but returned $value.',
      );
    }
    return value;
  }
}

/// Decides the delay before another execution of an Effect.
///
/// Returning null stops retrying and preserves the current typed failure.
/// Implementations must return a non-negative duration. Defects thrown by a
/// policy remain defects; they are never mapped into the Effect error channel.
abstract interface class RetryPolicy<E extends Object> {
  factory RetryPolicy.none() => _NoneRetryPolicy<E>();

  /// Retry with the same [delay] after every eligible typed failure.
  factory RetryPolicy.fixed({
    required int maxAttempts,
    required Duration delay,
    Duration? maxDelay,
    bool jitter = false,
  }) {
    _validateRetryAttempts(maxAttempts);
    _validateRetryDuration(delay, 'delay');
    _validateOptionalRetryDuration(maxDelay, 'maxDelay');
    return _FixedRetryPolicy<E>(
      maxAttempts: maxAttempts,
      delay: delay,
      maxDelay: maxDelay,
      jitter: jitter,
    );
  }

  /// Increase the delay by [increment] after each failed attempt.
  ///
  /// When [increment] is omitted, [initialDelay] is used. The delay after the
  /// first failed attempt is [initialDelay].
  factory RetryPolicy.linear({
    required int maxAttempts,
    required Duration initialDelay,
    Duration? increment,
    Duration? maxDelay,
    bool jitter = false,
  }) {
    _validateRetryAttempts(maxAttempts);
    _validateRetryDuration(initialDelay, 'initialDelay');
    final effectiveIncrement = increment ?? initialDelay;
    _validateRetryDuration(effectiveIncrement, 'increment');
    _validateOptionalRetryDuration(maxDelay, 'maxDelay');
    return _LinearRetryPolicy<E>(
      maxAttempts: maxAttempts,
      initialDelay: initialDelay,
      increment: effectiveIncrement,
      maxDelay: maxDelay,
      jitter: jitter,
    );
  }

  /// Multiply the delay by [factor] after each failed attempt.
  ///
  /// The first failed attempt uses [initialDelay]. With the default factor of
  /// two, later delays are `initialDelay * 2`, `initialDelay * 4`, and so on.
  factory RetryPolicy.exponential({
    required int maxAttempts,
    required Duration initialDelay,
    int factor = 2,
    Duration? maxDelay,
    bool jitter = false,
  }) {
    _validateRetryAttempts(maxAttempts);
    _validateRetryDuration(initialDelay, 'initialDelay');
    if (factor <= 0) {
      throw ArgumentError.value(factor, 'factor', 'must be positive');
    }
    _validateOptionalRetryDuration(maxDelay, 'maxDelay');
    return _ExponentialRetryPolicy<E>(
      maxAttempts: maxAttempts,
      initialDelay: initialDelay,
      factor: factor,
      maxDelay: maxDelay,
      jitter: jitter,
    );
  }

  /// Return the delay before the next attempt, or null to stop.
  Duration? nextDelay(RetryContext<E> context);
}

final class _NoneRetryPolicy<E extends Object> implements RetryPolicy<E> {
  const _NoneRetryPolicy();

  @override
  Duration? nextDelay(RetryContext<E> context) => null;
}

final class _FixedRetryPolicy<E extends Object> implements RetryPolicy<E> {
  const _FixedRetryPolicy({
    required this.maxAttempts,
    required this.delay,
    required this.maxDelay,
    required this.jitter,
  });

  final int maxAttempts;
  final Duration delay;
  final Duration? maxDelay;
  final bool jitter;

  @override
  Duration? nextDelay(RetryContext<E> context) {
    if (context.attempt >= maxAttempts) return null;
    final capped = _retryDurationFromMicroseconds(
      BigInt.from(delay.inMicroseconds),
      maxDelay,
    );
    return _applyRetryJitter(capped, context, jitter);
  }
}

final class _LinearRetryPolicy<E extends Object> implements RetryPolicy<E> {
  const _LinearRetryPolicy({
    required this.maxAttempts,
    required this.initialDelay,
    required this.increment,
    required this.maxDelay,
    required this.jitter,
  });

  final int maxAttempts;
  final Duration initialDelay;
  final Duration increment;
  final Duration? maxDelay;
  final bool jitter;

  @override
  Duration? nextDelay(RetryContext<E> context) {
    if (context.attempt >= maxAttempts) return null;

    final microseconds =
        BigInt.from(initialDelay.inMicroseconds) +
        BigInt.from(increment.inMicroseconds) *
            BigInt.from(context.attempt - 1);
    final delay = _retryDurationFromMicroseconds(microseconds, maxDelay);
    return _applyRetryJitter(delay, context, jitter);
  }
}

final class _ExponentialRetryPolicy<E extends Object>
    implements RetryPolicy<E> {
  const _ExponentialRetryPolicy({
    required this.maxAttempts,
    required this.initialDelay,
    required this.factor,
    required this.maxDelay,
    required this.jitter,
  });

  final int maxAttempts;
  final Duration initialDelay;
  final int factor;
  final Duration? maxDelay;
  final bool jitter;

  @override
  Duration? nextDelay(RetryContext<E> context) {
    if (context.attempt >= maxAttempts) return null;

    var microseconds = BigInt.from(initialDelay.inMicroseconds);
    final cap = maxDelay == null ? null : BigInt.from(maxDelay!.inMicroseconds);
    for (var exponent = 1; exponent < context.attempt; exponent++) {
      microseconds *= BigInt.from(factor);
      if (cap != null && microseconds >= cap) {
        microseconds = cap;
        break;
      }
      if (cap == null && microseconds > _maximumRetryDurationMicroseconds) {
        throw RangeError(
          'The exponential retry delay exceeds Duration range. '
          'Provide maxDelay to cap the policy.',
        );
      }
    }

    final delay = _retryDurationFromMicroseconds(microseconds, maxDelay);
    return _applyRetryJitter(delay, context, jitter);
  }
}

final BigInt _maximumRetryDurationMicroseconds = BigInt.parse(
  '9223372036854775807',
);

void _validateRetryAttempts(int maxAttempts) {
  if (maxAttempts <= 0) {
    throw ArgumentError.value(
      maxAttempts,
      'maxAttempts',
      'must be positive and includes the initial attempt',
    );
  }
}

void _validateRetryDuration(Duration duration, String name) {
  if (duration.isNegative) {
    throw ArgumentError.value(duration, name, 'must not be negative');
  }
}

void _validateOptionalRetryDuration(Duration? duration, String name) {
  if (duration != null) _validateRetryDuration(duration, name);
}

Duration _retryDurationFromMicroseconds(
  BigInt microseconds,
  Duration? maxDelay,
) {
  final cap = maxDelay == null ? null : BigInt.from(maxDelay.inMicroseconds);
  if (cap != null && microseconds > cap) return maxDelay!;
  if (microseconds > _maximumRetryDurationMicroseconds) {
    throw RangeError(
      'The retry delay exceeds Duration range. Provide maxDelay to cap it.',
    );
  }
  return Duration(microseconds: microseconds.toInt());
}

Duration _applyRetryJitter<E extends Object>(
  Duration delay,
  RetryContext<E> context,
  bool enabled,
) {
  if (!enabled || delay == Duration.zero) return delay;

  const precision = 1000000000;
  final sample = (context.nextRandom() * precision).floor();
  final microseconds =
      BigInt.from(delay.inMicroseconds) *
      BigInt.from(sample) ~/
      BigInt.from(precision);
  return Duration(microseconds: microseconds.toInt());
}
