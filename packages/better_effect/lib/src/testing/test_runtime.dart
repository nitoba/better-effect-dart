import 'dart:async';

import 'package:better_effect/better_effect.dart';

import 'recording_runtime_observer.dart';

/// Registers an asynchronous cleanup callback with the surrounding test runner.
typedef TestCleanupRegistrar = void Function(Future<void> Function() cleanup);

/// A test-owned Runtime with event recording and deterministic cleanup.
final class TestRuntime {
  TestRuntime._({
    required this.runtime,
    required this.observer,
    required List<RuntimeObserverError> observerErrors,
  }) : _observerErrors = observerErrors;

  /// Start a Runtime and automatically attach [RecordingRuntimeObserver].
  ///
  /// Pass [registerCleanup] from the test framework boundary to guarantee
  /// teardown without making `better_effect` depend on `package:test`:
  ///
  /// ```dart
  /// final harness = await TestRuntime.start(
  ///   module,
  ///   registerCleanup: (cleanup) => addTearDown(cleanup),
  /// );
  /// ```
  static Future<TestRuntime> start(
    Module module, {
    ResolverBackend? backend,
    CleanupFailureObserver? cleanupFailureObserver,
    Iterable<RuntimeObserver> observers = const <RuntimeObserver>[],
    RuntimeObserverErrorHandler? observerErrorHandler,
    TestCleanupRegistrar? registerCleanup,
  }) async {
    final recorder = RecordingRuntimeObserver();
    final errors = <RuntimeObserverError>[];
    final runtime = await module.start(
      backend: backend,
      cleanupFailureObserver: cleanupFailureObserver,
      observers: <RuntimeObserver>[recorder, ...observers],
      observerErrorHandler: (error) {
        errors.add(error);
        observerErrorHandler?.call(error);
      },
    );

    final harness = TestRuntime._(
      runtime: runtime,
      observer: recorder,
      observerErrors: errors,
    );
    registerCleanup?.call(() => harness.close());
    return harness;
  }

  /// Start a harness, execute [body], and close it even when [body] throws.
  static Future<T> use<T extends Object>(
    Module module,
    FutureOr<T> Function(TestRuntime testRuntime) body, {
    ResolverBackend? backend,
    CleanupFailureObserver? cleanupFailureObserver,
    Iterable<RuntimeObserver> observers = const <RuntimeObserver>[],
    RuntimeObserverErrorHandler? observerErrorHandler,
  }) async {
    final harness = await start(
      module,
      backend: backend,
      cleanupFailureObserver: cleanupFailureObserver,
      observers: observers,
      observerErrorHandler: observerErrorHandler,
    );

    Object? primaryError;
    StackTrace? primaryStackTrace;
    T? value;

    try {
      value = await Future<T>.sync(() => body(harness));
    } catch (error, stackTrace) {
      primaryError = error;
      primaryStackTrace = stackTrace;
    }

    try {
      await harness.close();
    } catch (closeError, closeStackTrace) {
      if (primaryError == null) {
        Error.throwWithStackTrace(closeError, closeStackTrace);
      }

      Error.throwWithStackTrace(
        CompositeDefect(
          primary: primaryError,
          primaryStackTrace: primaryStackTrace!,
          secondary: closeError,
          secondaryStackTrace: closeStackTrace,
        ),
        primaryStackTrace,
      );
    }

    if (primaryError != null) {
      Error.throwWithStackTrace(primaryError, primaryStackTrace!);
    }

    return value as T;
  }

  /// Underlying long-lived Runtime.
  final Runtime runtime;

  /// Ordered Runtime events emitted by this harness.
  final RecordingRuntimeObserver observer;

  final List<RuntimeObserverError> _observerErrors;

  /// Immutable snapshot of observer callback failures.
  ///
  /// The Runtime still treats these failures as best-effort instrumentation.
  List<RuntimeObserverError> get observerErrors {
    return List<RuntimeObserverError>.unmodifiable(_observerErrors);
  }

  bool _closed = false;

  /// Whether [close] has been requested through this harness.
  bool get isClosed => _closed;

  /// Boundary service access for test setup and assertions.
  Services get services => runtime.services;

  /// Managed executions that have not reached physical completion.
  Set<int> get activeExecutionIds => observer.activeExecutionIds;

  /// Fail when any managed execution is still physically owned by the Runtime.
  void assertNoActiveExecutions() {
    final active = activeExecutionIds;
    if (active.isEmpty) return;
    throw ActiveTestExecutionsException(active);
  }

  /// Start one managed execution.
  EffectExecution<A, E> execute<A extends Object, E extends Object>(
    Effect<A, E> effect, {
    String? label,
  }) {
    return runtime.execute(effect, label: label);
  }

  /// Run one Effect and return its Result.
  Future<ResultDart<A, E>> run<A extends Object, E extends Object>(
    Effect<A, E> effect, {
    String? executionLabel,
  }) {
    return runtime.run(effect, executionLabel: executionLabel);
  }

  /// Run one Effect while preserving every Exit case.
  Future<Exit<A, E>> runExit<A extends Object, E extends Object>(
    Effect<A, E> effect, {
    String? executionLabel,
  }) {
    return runtime.runExit(effect, executionLabel: executionLabel);
  }

  /// Start one execution with temporary providers and resources.
  EffectExecution<A, E> executeWith<A extends Object, E extends Object>(
    Module module,
    Effect<A, E> effect, {
    String? label,
  }) {
    return runtime.executeWith(module, effect, label: label);
  }

  /// Run one Effect with an execution-scoped Module.
  Future<ResultDart<A, E>> runWith<A extends Object, E extends Object>(
    Module module,
    Effect<A, E> effect, {
    String? executionLabel,
  }) {
    return runtime.runWith(module, effect, executionLabel: executionLabel);
  }

  /// Run one Effect with a temporary Module and preserve its Exit.
  Future<Exit<A, E>> runExitWith<A extends Object, E extends Object>(
    Module module,
    Effect<A, E> effect, {
    String? executionLabel,
  }) {
    return runtime.runExitWith(module, effect, executionLabel: executionLabel);
  }

  /// Close the Runtime and dispose the event recorder.
  Future<void> close({
    Duration gracePeriod = Duration.zero,
    bool interruptAfterGracePeriod = false,
  }) async {
    if (_closed) return;
    _closed = true;

    try {
      await runtime.close(
        gracePeriod: gracePeriod,
        interruptAfterGracePeriod: interruptAfterGracePeriod,
      );
    } finally {
      observer.dispose();
    }
  }
}

/// Raised when a test leaves managed physical work active.
final class ActiveTestExecutionsException implements Exception {
  ActiveTestExecutionsException(Iterable<int> executionIds)
    : executionIds = List<int>.unmodifiable(List<int>.of(executionIds)..sort());

  final List<int> executionIds;

  @override
  String toString() {
    return 'The test still owns active Effect executions: $executionIds. '
        'Complete or interrupt their physical work before asserting cleanup.';
  }
}
