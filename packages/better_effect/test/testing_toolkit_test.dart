import 'dart:async';

import 'package:auto_injector/auto_injector.dart' as auto;
import 'package:better_effect/testing.dart';
import 'package:test/test.dart';

final class TestFailure implements Exception {
  const TestFailure(this.message);

  final String message;
}

abstract interface class TestClock {
  String get value;
}

final class TestClockLive implements TestClock {
  const TestClockLive(this.value);

  @override
  final String value;
}

final class _DisposableService {
  const _DisposableService();
}

final class _BrokenFactoryBackend implements ResolverBackend {
  final ResolverBackend _delegate = AutoInjectorBackend();

  @override
  FutureOr<void> activate() => _delegate.activate();

  @override
  FutureOr<void> close() => _delegate.close();

  @override
  void commit() => _delegate.commit();

  @override
  void register<T extends Object>(
    Function constructor, {
    required Lifetime lifetime,
    String? key,
  }) {
    _delegate.register<T>(
      constructor,
      lifetime: lifetime == Lifetime.factory
          ? Lifetime.lazySingleton
          : lifetime,
      key: key,
    );
  }

  @override
  void registerInstance<T extends Object>(T instance, {String? key}) {
    _delegate.registerInstance<T>(instance, key: key);
  }

  @override
  T resolve<T extends Object>({String? key}) {
    return _delegate.resolve<T>(key: key);
  }
}

ResolverBackendDisposalProbe _autoInjectorDisposalProbe() {
  var disposed = false;
  final injector = auto.AutoInjector();
  injector.addLazySingleton<_DisposableService>(
    _DisposableService.new,
    config: auto.BindConfig<_DisposableService>(
      onDispose: (_) {
        disposed = true;
      },
    ),
  );
  final backend = AutoInjectorBackend(injector);

  return ResolverBackendDisposalProbe(
    backend: backend,
    instantiate: backend.resolve<_DisposableService>,
    wasDisposed: () => disposed,
  );
}

void main() {
  group('Exit testing helpers', () {
    test('match every Exit case and extract typed payloads', () {
      final success = ExitSuccess<int, TestFailure>(42);
      final failure = ExitFailure<int, TestFailure>(
        const TestFailure('expected'),
      );
      final defect = ExitDefect<int, TestFailure>(
        StateError('defect'),
        StackTrace.current,
      );
      final interrupted = ExitInterrupted<int, TestFailure>();

      expect(success, isExitSuccess<int, TestFailure>(42));
      expect(
        failure,
        isExitFailure<int, TestFailure>(
          isA<TestFailure>().having(
            (error) => error.message,
            'message',
            'expected',
          ),
        ),
      );
      expect(defect, isExitDefect<int, TestFailure>(isA<StateError>()));
      expect(interrupted, isExitInterrupted<int, TestFailure>());

      expect(expectExitSuccess(success), 42);
      expect(expectExitFailure(failure).message, 'expected');
      expect(expectExitDefect(defect).defect, isA<StateError>());
      expectExitInterrupted(interrupted);
    });

    test('typed extractors fail descriptively for the wrong Exit', () {
      final exit = ExitFailure<int, TestFailure>(const TestFailure('nope'));

      expect(
        () => expectExitSuccess(exit),
        throwsA(
          isA<BetterEffectTestExpectationException>().having(
            (error) => error.toString(),
            'message',
            contains('ExitSuccess<int, TestFailure>'),
          ),
        ),
      );
    });
  });

  group('deterministic test primitives', () {
    test('TestGate and TestSignal coordinate without sleeps', () async {
      final gate = TestGate<int>();
      final signal = TestSignal();
      final result = () async {
        await signal.wait;
        return gate.future;
      }();

      expect(signal.isSignalled, isFalse);
      signal.signal();
      expect(signal.isSignalled, isTrue);
      gate.complete(42);

      expect(await result, 42);
      expect(gate.isCompleted, isTrue);
      expect(
        () => gate.complete(43),
        throwsA(isA<TestGateAlreadyCompletedException>()),
      );
    });

    test('TestEventRecorder verifies exact lifecycle order', () {
      final recorder = TestEventRecorder<String>()
        ..record('acquire:database')
        ..record('acquire:transaction')
        ..record('release:transaction')
        ..record('release:database');

      recorder.expectEvents(const <String>[
        'acquire:database',
        'acquire:transaction',
        'release:transaction',
        'release:database',
      ]);
      expect(
        () => recorder.expectEvents(const <String>['wrong']),
        throwsA(isA<TestEventSequenceException<String>>()),
      );
    });
  });

  group('TestRuntime', () {
    test('records events and delegates execution-scoped operations', () async {
      final harness = await TestRuntime.start(
        Module([.instance<TestClock>(const TestClockLive('root'))]),
      );
      final event = harness.observer.next<ExecutionEndEvent>(
        where: (event) => event.context.executionLabel == 'clock.read',
      );

      try {
        final exit = await harness.runExit(
          Effect<String, TestFailure>.result((use) async {
            return use<TestClock>().value;
          }),
          executionLabel: 'clock.read',
        );
        final localExit = await harness.runExitWith(
          Module([.instance<String>('local-value')]),
          Effect<String, TestFailure>.result((use) async => use<String>()),
          executionLabel: 'local.read',
        );

        expect(exit, isExitSuccess<String, TestFailure>('root'));
        expect(localExit, isExitSuccess<String, TestFailure>('local-value'));
        expect((await event).outcome, same(exit));
        expect(harness.observer.eventsOf<ExecutionStartEvent>(), hasLength(2));
        expect(harness.observerErrors, isEmpty);
        harness.assertNoActiveExecutions();
      } finally {
        await harness.close();
      }

      expect(harness.isClosed, isTrue);
      expect(harness.observer.isDisposed, isTrue);
    });

    test(
      'registerCleanup gives ownership to the surrounding test runner',
      () async {
        Future<void> Function()? cleanup;
        final harness = await TestRuntime.start(
          Module(const <Binding>[]),
          registerCleanup: (callback) {
            cleanup = callback;
          },
        );

        expect(cleanup, isNotNull);
        expect(harness.isClosed, isFalse);
        await cleanup!();
        expect(harness.isClosed, isTrue);
      },
    );

    test(
      'active execution assertion detects forgotten physical work',
      () async {
        final harness = await TestRuntime.start(Module(const <Binding>[]));
        final started = TestSignal();
        final continueExecution = TestSignal();
        final execution = harness.execute(
          Effect<int, Never>.result((_) async {
            started.signal();
            await continueExecution.wait;
            return 42;
          }),
        );

        await started.wait;
        expect(
          harness.assertNoActiveExecutions,
          throwsA(
            isA<ActiveTestExecutionsException>().having(
              (error) => error.executionIds,
              'executionIds',
              contains(execution.id),
            ),
          ),
        );

        final completed = harness.observer.next<ExecutionEndEvent>(
          where: (event) => event.context.executionId == execution.id,
        );
        continueExecution.signal();
        expect(await execution.exit, isExitSuccess<int, Never>(42));
        await completed;
        harness.assertNoActiveExecutions();
        await harness.close();
      },
    );

    test('use closes the Runtime after success and failure', () async {
      Runtime? successfulRuntime;
      final value = await TestRuntime.use<int>(Module(const <Binding>[]), (
        harness,
      ) async {
        successfulRuntime = harness.runtime;
        return 42;
      });

      expect(value, 42);
      expect(successfulRuntime?.state, RuntimeState.closed);

      Runtime? failingRuntime;
      await expectLater(
        TestRuntime.use<int>(Module(const <Binding>[]), (harness) {
          failingRuntime = harness.runtime;
          throw StateError('body failed');
        }),
        throwsA(isA<StateError>()),
      );
      expect(failingRuntime?.state, RuntimeState.closed);
    });
  });

  group('RecordingRuntimeObserver', () {
    test('waiters receive only matching future events', () async {
      final recorder = RecordingRuntimeObserver();
      final matching = recorder.next<ExecutionStartEvent>(
        where: (event) => event.context.executionLabel == 'target',
      );
      final runtime = await Module(
        const <Binding>[],
      ).start(observers: <RuntimeObserver>[recorder]);

      try {
        await runtime.runExit(
          Effect<int, Never>.succeed(1),
          executionLabel: 'other',
        );
        await runtime.runExit(
          Effect<int, Never>.succeed(2),
          executionLabel: 'target',
        );

        expect((await matching).context.executionLabel, 'target');
        expect(recorder.eventsOf<ExecutionEndEvent>(), hasLength(2));
        expect(recorder.lastOf<ExecutionEndEvent>(), isNotNull);
        expect(recorder.activeExecutionIds, isEmpty);
      } finally {
        await runtime.close();
        recorder.dispose();
      }
    });

    test('disposing fails pending waiters', () async {
      final recorder = RecordingRuntimeObserver();
      final pending = recorder.next<ExecutionEndEvent>();
      final expectation = expectLater(
        pending,
        throwsA(isA<RecordingRuntimeObserverDisposedException>()),
      );

      recorder.dispose();

      await expectation;
    });
  });

  group('ResolverBackend compatibility kit', () {
    test('AutoInjectorBackend satisfies every supported scenario', () async {
      final report = await inspectResolverBackendContract(
        createBackend: AutoInjectorBackend.new,
        createDisposalProbe: _autoInjectorDisposalProbe,
      );

      expect(report.passed, isTrue, reason: '${report.failures.toList()}');
      expect(report.failures, isEmpty);
      expect(report.skipped, isEmpty);
      expect(
        report.results.map((result) => result.scenario).toSet(),
        ResolverBackendContractCase.values.toSet(),
      );
    });

    test('public run helper completes for a compatible backend', () async {
      await runResolverBackendContractTests(
        createBackend: AutoInjectorBackend.new,
        createDisposalProbe: _autoInjectorDisposalProbe,
      );
    });

    test('optional disposal capability is reported as skipped', () async {
      final report = await inspectResolverBackendContract(
        createBackend: AutoInjectorBackend.new,
      );

      final result = report.resultFor(
        ResolverBackendContractCase.instantiatedServicesAreDisposed,
      );
      expect(result.skipped, isTrue);
      expect(result.skipReason, contains('disposal callback'));
      expect(report.passed, isTrue);
    });

    test(
      'an intentionally broken backend reports an actionable scenario',
      () async {
        final report = await inspectResolverBackendContract(
          createBackend: () => _BrokenFactoryBackend(),
        );

        expect(report.passed, isFalse);
        final failure = report.resultFor(
          ResolverBackendContractCase.factoryCreatesFreshInstances,
        );
        expect(failure.failed, isTrue);
        expect(
          failure.error.toString(),
          allOf(
            contains('factoryCreatesFreshInstances'),
            contains('Factory reused the same instance'),
          ),
        );
        expect(
          report.throwIfFailed,
          throwsA(
            isA<ResolverBackendContractException>().having(
              (error) => error.toString(),
              'message',
              contains('factoryCreatesFreshInstances'),
            ),
          ),
        );
      },
    );
  });
}
