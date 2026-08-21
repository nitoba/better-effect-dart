import 'package:better_effect/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'registry.dart';

final class _Failure implements Exception {
  const _Failure(this.message);

  final String message;
}

final class _CleanupFailure implements Exception {
  const _CleanupFailure(this.message);

  final String message;
}

final class _Defect implements Exception {
  const _Defect(this.message);

  final String message;
}

final class _Resource {
  const _Resource(this.id);

  final int id;
}

final class _ThrowingObserver extends RuntimeObserver {
  @override
  void onExecutionStart(ExecutionStartEvent event) {
    throw StateError('observer start failed');
  }

  @override
  void onExecutionEnd(ExecutionEndEvent event) {
    throw StateError('observer end failed');
  }
}

void registerCoreEffectOutcomeScenarios() {
  conformanceTest('EFFECT-01', () async {
    var executions = 0;
    final effect = Effect<int, _Failure>.sync(() {
      executions++;
      return 42;
    }).map((value) => value + 1);

    expect(executions, 0);
    final exit = await Module(const <Binding>[]).runExit(effect);

    expect(expectExitSuccess(exit), 43);
    expect(executions, 1);
  });

  conformanceTest('EFFECT-02', () async {
    const failure = _Failure('typed');
    final exit = await Module(const <Binding>[]).runExit(
      Effect<int, _Failure>.result((use) async {
        use.fail(failure);
      }),
    );

    expect(expectExitFailure(exit), same(failure));
  });

  conformanceTest('EFFECT-03', () async {
    final exit = await Module(
      const <Binding>[],
    ).runExit(Effect<int, _Failure>.sync(() => throw const _Defect('boom')));

    expect(expectExitDefect(exit).defect, isA<_Defect>());
  });

  conformanceTest('EFFECT-04', () async {
    const bindings = <Binding>[];
    final success = await Module(
      bindings,
    ).run(Effect<int, _Failure>.succeed(7));
    final failure = await Module(
      bindings,
    ).run(Effect<int, _Failure>.fail(const _Failure('expected')));
    final defect = await Module(bindings).runExit(
      Effect<int, _Failure>.sync(() => throw const _Defect('unexpected')),
    );

    expect(success.getOrNull(), 7);
    expect(failure.exceptionOrNull(), isA<_Failure>());
    expect(defect, isA<ExitDefect<int, _Failure>>());
  });

  conformanceTest('EFFECT-05', () async {
    final harness = await TestRuntime.start(Module(const <Binding>[]));
    final started = TestSignal();
    final continueWork = TestSignal();
    final ended = harness.observer.next<ExecutionEndEvent>();
    final execution = harness.execute(
      Effect<int, Never>.result((_) async {
        started.signal();
        await continueWork.wait;
        return 42;
      }),
    );

    await started.wait;
    expect(execution.interrupt(reason: 'conformance'), isTrue);
    expect(await execution.exit, isExitInterrupted<int, Never>());
    expect(execution.isRunning, isTrue);

    continueWork.signal();
    await ended;
    await Future<void>.value();
    expect(execution.isRunning, isFalse);
    await harness.close();
  });

  conformanceTest('OUTCOME-01', () async {
    var releases = 0;
    final runtime = await Module(const <Binding>[]).start();
    final exit = await runtime.runExit(
      Effect<int, _Failure>.result((use) async {
        await use.acquire(
          Effect<_Resource, _Failure>.succeed(const _Resource(1)),
          release: (_, _) {
            releases++;
          },
        );
        return 42;
      }),
    );

    expect(expectExitSuccess(exit), 42);
    expect(releases, 1);
    await runtime.close();
  });

  conformanceTest('OUTCOME-02', () async {
    final runtime = await Module(const <Binding>[]).start();
    final exit = await runtime.runExit(
      Effect<int, _Failure>.result((use) async {
        await use.acquire(
          Effect<_Resource, _Failure>.succeed(const _Resource(1)),
          release: (_, _) => throw const _CleanupFailure('cleanup'),
        );
        return 42;
      }),
    );

    final release = expectExitDefect(exit).defect as ScopeReleaseException;
    expect(release.failures, hasLength(1));
    expect(release.failures.single.error, isA<_CleanupFailure>());
    await runtime.close();
  });

  conformanceTest('OUTCOME-03', () async {
    const failure = _Failure('typed');
    var releases = 0;
    final runtime = await Module(const <Binding>[]).start();
    final exit = await runtime.runExit(
      Effect<int, _Failure>.result((use) async {
        await use.acquire(
          Effect<_Resource, _Failure>.succeed(const _Resource(1)),
          release: (_, _) {
            releases++;
          },
        );
        use.fail(failure);
      }),
    );

    expect(expectExitFailure(exit), same(failure));
    expect(releases, 1);
    await runtime.close();
  });

  conformanceTest('OUTCOME-04', () async {
    const failure = _Failure('typed');
    final diagnostics = <CleanupFailureDiagnostic>[];
    final runtime = await Module(
      const <Binding>[],
    ).start(cleanupFailureObserver: diagnostics.add);
    final exit = await runtime.runExit(
      Effect<int, _Failure>.result((use) async {
        await use.acquire(
          Effect<_Resource, _Failure>.succeed(const _Resource(1)),
          release: (_, _) => throw const _CleanupFailure('cleanup'),
        );
        use.fail(failure);
      }),
    );

    expect(expectExitFailure(exit), same(failure));
    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.outcome, same(exit));
    expect(
      diagnostics.single.error.failures.single.error,
      isA<_CleanupFailure>(),
    );
    await runtime.close();
  });

  conformanceTest('OUTCOME-05', () async {
    const defect = _Defect('primary');
    var releases = 0;
    final runtime = await Module(const <Binding>[]).start();
    final exit = await runtime.runExit(
      Effect<int, _Failure>.result((use) async {
        await use.acquire(
          Effect<_Resource, _Failure>.succeed(const _Resource(1)),
          release: (_, _) {
            releases++;
          },
        );
        throw defect;
      }),
    );

    expect(expectExitDefect(exit).defect, same(defect));
    expect(releases, 1);
    await runtime.close();
  });

  conformanceTest('OUTCOME-06', () async {
    const primary = _Defect('primary');
    final runtime = await Module(const <Binding>[]).start();
    final exit = await runtime.runExit(
      Effect<int, _Failure>.result((use) async {
        await use.acquire(
          Effect<_Resource, _Failure>.succeed(const _Resource(1)),
          release: (_, _) => throw const _CleanupFailure('cleanup'),
        );
        throw primary;
      }),
    );

    final defect = expectExitDefect(exit).defect as CompositeDefect;
    expect(defect.primary, same(primary));
    final release = defect.secondary as ScopeReleaseException;
    expect(release.failures.single.error, isA<_CleanupFailure>());
    await runtime.close();
  });

  conformanceTest('OUTCOME-07', () async {
    final harness = await TestRuntime.start(Module(const <Binding>[]));
    final started = TestSignal();
    final continueWork = TestSignal();
    final ended = harness.observer.next<ExecutionEndEvent>();
    var releases = 0;
    final execution = harness.execute(
      Effect<int, Never>.result((use) async {
        await use.acquire(
          Effect<_Resource, Never>.succeed(const _Resource(1)),
          release: (_, _) {
            releases++;
          },
        );
        started.signal();
        await continueWork.wait;
        return 42;
      }),
    );

    await started.wait;
    expect(execution.interrupt(reason: 'conformance'), isTrue);
    expect(await execution.exit, isExitInterrupted<int, Never>());
    expect(releases, 0);

    continueWork.signal();
    await ended;
    expect(releases, 1);
    await harness.close();
  });

  conformanceTest('OUTCOME-08', () async {
    final diagnostics = <CleanupFailureDiagnostic>[];
    final runtime = await Module(
      const <Binding>[],
    ).start(cleanupFailureObserver: diagnostics.add);
    final started = TestSignal();
    final continueWork = TestSignal();
    final execution = runtime.execute(
      Effect<int, Never>.result((use) async {
        await use.acquire(
          Effect<_Resource, Never>.succeed(const _Resource(1)),
          release: (_, _) => throw const _CleanupFailure('cleanup'),
        );
        started.signal();
        await continueWork.wait;
        return 42;
      }),
    );

    await started.wait;
    expect(execution.interrupt(reason: 'conformance'), isTrue);
    final logical = await execution.exit;
    expect(logical, isExitInterrupted<int, Never>());

    continueWork.signal();
    await expectLater(runtime.close(), throwsA(isA<ScopeReleaseException>()));
    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.outcome, same(logical));
    expect(
      diagnostics.single.error.failures.single.error,
      isA<_CleanupFailure>(),
    );
    expect(runtime.state, RuntimeState.closed);
  });

  conformanceTest('OUTCOME-09', () async {
    final observerErrors = <RuntimeObserverError>[];
    final runtime = await Module(const <Binding>[]).start(
      observers: <RuntimeObserver>[_ThrowingObserver()],
      observerErrorHandler: observerErrors.add,
    );

    final exit = await runtime.runExit(Effect<int, _Failure>.succeed(42));

    expect(expectExitSuccess(exit), 42);
    await runtime.close();
    expect(
      observerErrors.map((error) => error.callback).toSet(),
      <RuntimeObserverCallback>{
        RuntimeObserverCallback.executionStart,
        RuntimeObserverCallback.executionEnd,
      },
    );
  });
}
