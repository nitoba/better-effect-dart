import 'package:better_effect/better_effect.dart';

final class BenchmarkFailure implements Exception {
  const BenchmarkFailure();
}

Future<void> main() async {
  const warmupIterations = 1000;
  const measuredIterations = 10000;
  final runtime = await Module(const <Binding>[]).start();

  try {
    await _measure(runtime, const _RetryScenario.success(), warmupIterations);
    await _measure(runtime, const _RetryScenario.oneRetry(), warmupIterations);
    await _measure(
      runtime,
      const _RetryScenario.fiveAttempts(),
      warmupIterations,
    );

    final success = await _measure(
      runtime,
      const _RetryScenario.success(),
      measuredIterations,
    );
    final oneRetry = await _measure(
      runtime,
      const _RetryScenario.oneRetry(),
      measuredIterations,
    );
    final fiveAttempts = await _measure(
      runtime,
      const _RetryScenario.fiveAttempts(),
      measuredIterations,
    );

    _printResult('success without retry', success, measuredIterations);
    _printResult('one zero-delay retry', oneRetry, measuredIterations);
    _printResult('five zero-delay attempts', fiveAttempts, measuredIterations);
  } finally {
    await runtime.close();
  }
}

Future<Duration> _measure(
  Runtime runtime,
  _RetryScenario scenario,
  int iterations,
) async {
  final stopwatch = Stopwatch()..start();
  for (var iteration = 0; iteration < iterations; iteration++) {
    var attempts = 0;
    final effect =
        Effect<int, BenchmarkFailure>.result((use) async {
          attempts++;
          if (attempts < scenario.successAttempt) {
            use.fail(const BenchmarkFailure());
          }
          return attempts;
        }).retry(
          RetryPolicy.fixed(
            maxAttempts: scenario.maxAttempts,
            delay: Duration.zero,
          ),
        );

    await runtime.runExit(effect);
  }
  stopwatch.stop();
  return stopwatch.elapsed;
}

void _printResult(String label, Duration elapsed, int iterations) {
  final nanosecondsPerOperation = (elapsed.inMicroseconds * 1000) / iterations;
  print(
    '$label: ${elapsed.inMilliseconds} ms total, '
    '${nanosecondsPerOperation.toStringAsFixed(1)} ns/op',
  );
}

final class _RetryScenario {
  const _RetryScenario._({
    required this.successAttempt,
    required this.maxAttempts,
  });

  const _RetryScenario.success() : this._(successAttempt: 1, maxAttempts: 1);

  const _RetryScenario.oneRetry() : this._(successAttempt: 2, maxAttempts: 2);

  const _RetryScenario.fiveAttempts()
    : this._(successAttempt: 5, maxAttempts: 5);

  final int successAttempt;
  final int maxAttempts;
}
