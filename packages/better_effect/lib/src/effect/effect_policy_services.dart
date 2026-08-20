part of '../../better_effect.dart';

/// A replaceable source of wall-clock time and cooperative delays.
///
/// `better_effect` never installs an [EffectClock] implicitly. Applications
/// that use delayed retry or other timing policies must register one through an
/// ordinary [Module] binding or provide an implementation through an Effect
/// override.
abstract interface class EffectClock {
  /// Current host time.
  DateTime now();

  /// Wait for [duration] while observing [cancellation].
  ///
  /// Implementations must reject negative durations. A cancellation request is
  /// cooperative: it ends this wait, but it cannot forcefully cancel unrelated
  /// Dart Futures.
  Future<void> sleep(Duration duration, CancellationSignal cancellation);
}

/// Host-backed [EffectClock] using `DateTime.now` and `Future.delayed`.
final class SystemEffectClock implements EffectClock {
  const SystemEffectClock();

  @override
  DateTime now() => DateTime.now();

  @override
  Future<void> sleep(Duration duration, CancellationSignal cancellation) async {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }

    cancellation.throwIfCancelled();
    if (duration == Duration.zero) {
      await Future<void>.value();
      cancellation.throwIfCancelled();
      return;
    }

    await Future.any<void>(<Future<void>>[
      Future<void>.delayed(duration),
      cancellation.whenCancelled,
    ]);
    cancellation.throwIfCancelled();
  }
}

/// A replaceable source of uniform random values for Effect policies.
///
/// Implementations must return finite values in the half-open interval
/// `[0, 1)`. The service is required only when a policy actually requests
/// randomness, such as full-jitter retry.
abstract interface class EffectRandom {
  double nextDouble();
}

/// Host-backed pseudo-random source.
final class SystemEffectRandom implements EffectRandom {
  SystemEffectRandom() : _random = math.Random();

  final math.Random _random;

  @override
  double nextDouble() => _random.nextDouble();
}

/// Reproducible pseudo-random source for tests and deterministic simulations.
final class SeededEffectRandom implements EffectRandom {
  SeededEffectRandom(int seed) : _random = math.Random(seed);

  final math.Random _random;

  @override
  double nextDouble() => _random.nextDouble();
}
