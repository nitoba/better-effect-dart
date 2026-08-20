import 'package:better_effect/better_effect.dart';

abstract interface class BenchmarkClock {
  int now();
}

final class BenchmarkClockLive implements BenchmarkClock {
  const BenchmarkClockLive();

  @override
  int now() => 1;
}

final class NoopRuntimeObserver extends RuntimeObserver {
  const NoopRuntimeObserver();
}

Future<void> main() async {
  const warmupIterations = 2000;
  const measuredIterations = 20000;
  final module = Module([
    .instance<BenchmarkClock>(const BenchmarkClockLive()),
  ]);
  final effect = Effect<int, Never>.result((use) async {
    return use<BenchmarkClock>().now();
  });

  final withoutObservers = await module.start();
  final withObserver = await module.start(
    observers: const <RuntimeObserver>[NoopRuntimeObserver()],
  );

  try {
    await _run(withoutObservers, effect, warmupIterations);
    await _run(withObserver, effect, warmupIterations);

    final baseline = await _run(withoutObservers, effect, measuredIterations);
    final observed = await _run(withObserver, effect, measuredIterations);

    _printResult('no observers', baseline, measuredIterations);
    _printResult('one no-op observer', observed, measuredIterations);

    final baselineMicros = baseline.inMicroseconds;
    final overhead = baselineMicros == 0
        ? 0.0
        : ((observed.inMicroseconds - baselineMicros) / baselineMicros) * 100;
    print('relative observer overhead: ${overhead.toStringAsFixed(2)}%');
  } finally {
    await withoutObservers.close();
    await withObserver.close();
  }
}

Future<Duration> _run(
  Runtime runtime,
  Effect<int, Never> effect,
  int iterations,
) async {
  final stopwatch = Stopwatch()..start();
  for (var index = 0; index < iterations; index++) {
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
