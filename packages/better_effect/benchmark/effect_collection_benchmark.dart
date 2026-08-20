import 'package:better_effect/better_effect.dart';

Future<void> main() async {
  const warmupIterations = 20;
  const measuredIterations = 100;
  const itemCount = 512;
  final inputs = List<int>.generate(itemCount, (index) => index);
  final module = Module(const <Binding>[]);
  final runtime = await module.start();

  final sequential = Effect.forEach(
    inputs,
    (value) => Effect<int, Never>.succeed(value + 1),
  );
  final bounded = Effect.forEach(
    inputs,
    (value) => Effect<int, Never>.succeed(value + 1),
    concurrency: 8,
  );
  final unbounded = Effect.forEachUnbounded(
    inputs,
    (value) => Effect<int, Never>.succeed(value + 1),
  );

  try {
    await _run(runtime, sequential, warmupIterations);
    await _run(runtime, bounded, warmupIterations);
    await _run(runtime, unbounded, warmupIterations);

    final sequentialTime = await _run(runtime, sequential, measuredIterations);
    final boundedTime = await _run(runtime, bounded, measuredIterations);
    final unboundedTime = await _run(runtime, unbounded, measuredIterations);

    _printResult('sequential (1 worker)', sequentialTime, measuredIterations);
    _printResult('bounded (8 workers)', boundedTime, measuredIterations);
    _printResult('explicit unbounded', unboundedTime, measuredIterations);
  } finally {
    await runtime.close();
  }
}

Future<Duration> _run(
  Runtime runtime,
  Effect<List<int>, Never> effect,
  int iterations,
) async {
  final stopwatch = Stopwatch()..start();
  for (var index = 0; index < iterations; index++) {
    final exit = await runtime.runExit(effect);
    if (exit case ExitSuccess<List<int>, Never>(:final value)) {
      if (value.length != 512) {
        throw StateError('Unexpected collection result length.');
      }
    } else {
      throw StateError('Collection benchmark did not succeed: $exit');
    }
  }
  stopwatch.stop();
  return stopwatch.elapsed;
}

void _printResult(String label, Duration elapsed, int iterations) {
  final microsecondsPerRun = elapsed.inMicroseconds / iterations;
  print(
    '$label: ${elapsed.inMilliseconds} ms total, '
    '${microsecondsPerRun.toStringAsFixed(1)} µs/run',
  );
}
