import 'package:better_effect/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'registry.dart';

final class _BatchFailure implements Exception {
  const _BatchFailure(this.index);

  final int index;
}

final class _RetryFailure implements Exception {
  const _RetryFailure(this.code);

  final int code;
}

final class _RetryResource {
  const _RetryResource(this.attempt);

  final int attempt;
}

void registerCoreConcurrencyRetryScenarios() {
  conformanceTest('CONCURRENCY-01', () async {
    final gates = List<TestSignal>.generate(4, (_) => TestSignal());
    final firstWindowStarted = TestSignal();
    var active = 0;
    var maximumActive = 0;
    var started = 0;
    final runtime = await Module(const <Binding>[]).start();
    final execution = runtime.execute(
      Effect.forEach(
        const <int>[0, 1, 2, 3],
        (index) => Effect<int, _BatchFailure>.result((_) async {
          active++;
          started++;
          if (active > maximumActive) maximumActive = active;
          if (started == 2) firstWindowStarted.signal();
          await gates[index].wait;
          active--;
          return index;
        }),
        concurrency: 2,
      ),
    );

    await firstWindowStarted.wait;
    expect(maximumActive, 2);

    for (final gate in gates) {
      gate.signal();
    }
    expect(expectExitSuccess(await execution.exit), <int>[0, 1, 2, 3]);
    expect(maximumActive, 2);
    await runtime.close();
  });

  conformanceTest('CONCURRENCY-02', () async {
    final gates = List<TestGate<int>>.generate(3, (_) => TestGate<int>());
    final allStarted = TestSignal();
    var started = 0;
    final runtime = await Module(const <Binding>[]).start();
    final execution = runtime.execute(
      Effect.forEach(
        const <int>[0, 1, 2],
        (index) => Effect<int, _BatchFailure>.result((_) async {
          started++;
          if (started == 3) allStarted.signal();
          return gates[index].future;
        }),
        concurrency: 3,
      ),
    );

    await allStarted.wait;
    gates[2].complete(30);
    gates[0].complete(10);
    gates[1].complete(20);

    expect(expectExitSuccess(await execution.exit), <int>[10, 20, 30]);
    await runtime.close();
  });

  conformanceTest('CONCURRENCY-03', () async {
    final typedGates = List<TestSignal>.generate(3, (_) => TestSignal());
    final typedStarted = TestSignal();
    final laterFailureReturned = TestSignal();
    var typedStartCount = 0;
    final typedRuntime = await Module(const <Binding>[]).start();
    final typedExecution = typedRuntime.execute(
      Effect.forEach(
        const <int>[0, 1, 2, 3],
        (index) => Effect<int, _BatchFailure>.result((use) async {
          typedStartCount++;
          if (typedStartCount == 3) typedStarted.signal();
          await typedGates[index].wait;
          if (index == 2) {
            laterFailureReturned.signal();
            use.fail(const _BatchFailure(2));
          }
          if (index == 0) use.fail(const _BatchFailure(0));
          return index;
        }),
        concurrency: 3,
      ),
    );

    await typedStarted.wait;
    typedGates[2].signal();
    await laterFailureReturned.wait;
    await Future<void>.value();
    typedGates[0].signal();
    typedGates[1].signal();

    expect(expectExitFailure(await typedExecution.exit).index, 0);
    expect(typedStartCount, 3);
    await typedRuntime.close();

    final defectGates = List<TestSignal>.generate(3, (_) => TestSignal());
    final defectStarted = TestSignal();
    final laterDefectReturned = TestSignal();
    var defectStartCount = 0;
    final defectRuntime = await Module(const <Binding>[]).start();
    final defectExecution = defectRuntime.execute(
      Effect.forEach(
        const <int>[0, 1, 2],
        (index) => Effect<int, _BatchFailure>.result((_) async {
          defectStartCount++;
          if (defectStartCount == 3) defectStarted.signal();
          await defectGates[index].wait;
          if (index == 2) {
            laterDefectReturned.signal();
            throw StateError('defect-2');
          }
          if (index == 0) throw StateError('defect-0');
          return index;
        }),
        concurrency: 3,
      ),
    );

    await defectStarted.wait;
    defectGates[2].signal();
    await laterDefectReturned.wait;
    await Future<void>.value();
    defectGates[0].signal();
    defectGates[1].signal();

    final defect = expectExitDefect(await defectExecution.exit).defect;
    expect(defect, isA<StateError>());
    expect((defect as StateError).message, 'defect-0');
    await defectRuntime.close();
  });

  conformanceTest('CONCURRENCY-04', () async {
    final first = TestSignal();
    final second = TestSignal();
    final firstWindowStarted = TestSignal();
    final failureReturned = TestSignal();
    final started = <int>[];
    final runtime = await Module(const <Binding>[]).start();
    final execution = runtime.execute(
      Effect.forEach(
        const <int>[0, 1, 2, 3, 4],
        (index) => Effect<int, _BatchFailure>.result((use) async {
          started.add(index);
          if (started.length == 2) firstWindowStarted.signal();
          if (index == 0) await first.wait;
          if (index == 1) await second.wait;
          if (index == 1) {
            failureReturned.signal();
            use.fail(const _BatchFailure(1));
          }
          return index;
        }),
        concurrency: 2,
      ),
    );

    await firstWindowStarted.wait;
    second.signal();
    await failureReturned.wait;
    await Future<void>.value();
    expect(started, <int>[0, 1]);

    first.signal();
    expect(expectExitFailure(await execution.exit).index, 1);
    expect(started, <int>[0, 1]);
    await runtime.close();
  });

  conformanceTest('CONCURRENCY-05', () async {
    final first = TestSignal();
    final second = TestSignal();
    final firstWindowStarted = TestSignal();
    final started = <int>[];
    final harness = await TestRuntime.start(Module(const <Binding>[]));
    final ended = harness.observer.next<ExecutionEndEvent>();
    final execution = harness.execute(
      Effect.forEach(
        const <int>[0, 1, 2, 3],
        (index) => Effect<int, _BatchFailure>.result((_) async {
          started.add(index);
          if (started.length == 2) firstWindowStarted.signal();
          if (index == 0) await first.wait;
          if (index == 1) await second.wait;
          return index;
        }),
        concurrency: 2,
      ),
    );

    await firstWindowStarted.wait;
    expect(execution.interrupt(reason: 'conformance'), isTrue);
    expect(await execution.exit, isExitInterrupted<List<int>, _BatchFailure>());
    expect(started, <int>[0, 1]);

    first.signal();
    second.signal();
    await ended;
    await Future<void>.value();
    expect(started, <int>[0, 1]);
    expect(execution.isRunning, isFalse);
    await harness.close();
  });

  conformanceTest('RETRY-01', () async {
    var attempts = 0;
    final exit = await Module(const <Binding>[]).runExit(
      Effect<int, _RetryFailure>.result((use) async {
        attempts++;
        use.fail(_RetryFailure(attempts));
      }).retry(RetryPolicy.fixed(maxAttempts: 3, delay: Duration.zero)),
    );

    expect(expectExitFailure(exit).code, 3);
    expect(attempts, 3);
  });

  conformanceTest('RETRY-02', () async {
    var attempts = 0;
    final exit = await Module(const <Binding>[]).runExit(
      Effect<int, _RetryFailure>.sync(() {
        attempts++;
        throw StateError('defect');
      }).retry(RetryPolicy.fixed(maxAttempts: 5, delay: Duration.zero)),
    );

    expect(expectExitDefect(exit).defect, isA<StateError>());
    expect(attempts, 1);
  });

  conformanceTest('RETRY-03', () async {
    final events = <String>[];
    var attempts = 0;
    final exit = await Module(const <Binding>[]).runExit(
      Effect<int, _RetryFailure>.result((use) async {
        attempts++;
        final attempt = attempts;
        final resource = await use.acquire(
          Effect<_RetryResource, _RetryFailure>.sync(() {
            events.add('acquire:$attempt');
            return _RetryResource(attempt);
          }),
          release: (value, _) {
            events.add('release:${value.attempt}');
          },
        );
        events.add('use:${resource.attempt}');
        if (attempt == 1) use.fail(const _RetryFailure(1));
        return 42;
      }).retry(RetryPolicy.fixed(maxAttempts: 2, delay: Duration.zero)),
    );

    expect(expectExitSuccess(exit), 42);
    expect(events, <String>[
      'acquire:1',
      'use:1',
      'release:1',
      'acquire:2',
      'use:2',
      'release:2',
    ]);
  });

  conformanceTest('RETRY-04', () async {
    final harness = await TestRuntime.start(Module(const <Binding>[]));
    final started = TestSignal();
    final ended = harness.observer.next<ExecutionEndEvent>();
    var interruptedAttempts = 0;
    final interrupted = harness.execute(
      Effect<int, _RetryFailure>.result((use) async {
        interruptedAttempts++;
        started.signal();
        await use.cancellation.whenCancelled;
        use.cancellation.throwIfCancelled();
        return 1;
      }).retry(RetryPolicy.fixed(maxAttempts: 3, delay: Duration.zero)),
    );

    await started.wait;
    expect(interrupted.interrupt(reason: 'conformance'), isTrue);
    expect(await interrupted.exit, isExitInterrupted<int, _RetryFailure>());
    await ended;
    expect(interruptedAttempts, 1);
    await harness.close();

    final diagnostics = <CleanupFailureDiagnostic>[];
    final runtime = await Module(
      const <Binding>[],
    ).start(cleanupFailureObserver: diagnostics.add);
    var cleanupAttempts = 0;
    final cleanupExit = await runtime.runExit(
      Effect<int, _RetryFailure>.result((use) async {
        cleanupAttempts++;
        await use.acquire(
          Effect<_RetryResource, _RetryFailure>.succeed(
            _RetryResource(cleanupAttempts),
          ),
          release: (_, _) => throw StateError('attempt cleanup failed'),
        );
        use.fail(const _RetryFailure(503));
      }).retry(RetryPolicy.fixed(maxAttempts: 3, delay: Duration.zero)),
    );

    expect(expectExitFailure(cleanupExit).code, 503);
    expect(cleanupAttempts, 1);
    expect(diagnostics, hasLength(1));
    await runtime.close();
  });
}
