part of '../../better_effect.dart';

/// Lifecycle state of a [Runtime].
enum RuntimeState {
  /// The Runtime accepts new Effect executions.
  active,

  /// The Runtime rejects new executions and is draining active ones.
  closing,

  /// The Runtime has released its scopes and backend.
  closed,
}

final class _CancellationRequested implements Exception {
  const _CancellationRequested();
}

/// A cooperative cancellation signal exposed to an active Effect.
///
/// A signal request does not cancel arbitrary Dart Futures. Code using a
/// cancellable API can observe [isCancelled], await [whenCancelled], or call
/// [throwIfCancelled] at a cooperative boundary.
final class CancellationSignal {
  CancellationSignal._();

  final Completer<void> _whenCancelled = Completer<void>.sync();
  bool _isCancelled = false;
  Object? _reason;

  /// Whether cancellation has been requested.
  bool get isCancelled => _isCancelled;

  /// The first cancellation reason supplied by the execution owner.
  Object? get reason => _reason;

  /// Completes when cancellation is requested.
  Future<void> get whenCancelled => _whenCancelled.future;

  /// Stop at this cooperative boundary when cancellation was requested.
  void throwIfCancelled() {
    if (_isCancelled) {
      throw const _CancellationRequested();
    }
  }

  bool _cancel(Object? reason) {
    if (_isCancelled) {
      return false;
    }

    _isCancelled = true;
    _reason = reason;
    _whenCancelled.complete();
    return true;
  }
}

/// A managed handle for one Effect execution.
///
/// [exit] is the caller-visible logical result. [isRunning] describes physical
/// ownership, which can remain true after interruption while an arbitrary Dart
/// Future finishes and its Scope is cleaned up.
abstract interface class EffectExecution<A extends Object, E extends Object> {
  /// Monotonically increasing identifier within the owning Runtime.
  int get id;

  /// Optional diagnostic label supplied when execution started.
  String? get label;

  /// Whether physical work or Scope cleanup is still owned by the Runtime.
  bool get isRunning;

  /// Whether cooperative interruption has been requested.
  bool get isInterrupted;

  /// The caller-visible success, typed failure, defect, or interruption.
  Future<Exit<A, E>> get exit;

  /// Request cooperative interruption.
  ///
  /// The logical [exit] becomes [ExitInterrupted] immediately when no previous
  /// outcome was published. Physical work remains owned until it finishes.
  /// Returns false when interruption was already requested or physical work has
  /// completed.
  bool interrupt({Object? reason});
}

abstract interface class _RuntimeExecution {
  int get id;
  String? get label;
  Scope get scope;
  CancellationSignal get cancellation;
  Future<void> get completed;
  bool get isCompleted;
  void requestInterruption(Object? reason);
}

final class _EffectExecutionImpl<A extends Object, E extends Object>
    implements EffectExecution<A, E>, _RuntimeExecution {
  _EffectExecutionImpl({
    required this.id,
    required this.scope,
    required this.label,
  }) : cancellation = CancellationSignal._();

  @override
  final int id;

  @override
  final Scope scope;

  @override
  final String? label;

  @override
  final CancellationSignal cancellation;

  final Completer<Exit<A, E>> _exit = Completer<Exit<A, E>>.sync();
  final Completer<void> _completed = Completer<void>.sync();
  Exit<A, E>? _publishedExit;

  @override
  Future<Exit<A, E>> get exit => _exit.future;

  @override
  Future<void> get completed => _completed.future;

  @override
  bool get isCompleted => _completed.isCompleted;

  @override
  bool get isRunning => !isCompleted;

  @override
  bool get isInterrupted => cancellation.isCancelled;

  bool get hasPublishedExit => _exit.isCompleted;

  Exit<A, E>? get publishedExit => _publishedExit;

  @override
  bool interrupt({Object? reason}) {
    if (isCompleted || !cancellation._cancel(reason)) {
      return false;
    }

    completeLogical(ExitInterrupted<A, E>());
    return true;
  }

  @override
  void requestInterruption(Object? reason) {
    cancellation._cancel(reason);
  }

  void completeLogical(Exit<A, E> value) {
    if (_exit.isCompleted) {
      return;
    }

    _publishedExit = value;
    _exit.complete(value);
  }

  void completeLogicalError(Object error, StackTrace stackTrace) {
    if (_exit.isCompleted) {
      return;
    }

    _exit.completeError(error, stackTrace);
  }

  void completePhysical() {
    if (!_completed.isCompleted) {
      _completed.complete();
    }
  }
}

/// Executes Effects against the environment built from a [Module].
final class Runtime {
  Runtime._(this._rootContext, this._cleanupFailureObserver);

  final _RuntimeContext _rootContext;
  final CleanupFailureObserver? _cleanupFailureObserver;
  final Set<_RuntimeExecution> _activeExecutions = <_RuntimeExecution>{};
  final List<ReleaseFailure> _deferredExecutionFailures = <ReleaseFailure>[];
  int _nextExecutionId = 0;
  RuntimeState _state = RuntimeState.active;
  Future<void>? _closingFuture;

  /// Build a runtime, install constructor bindings, and acquire resources.
  static Future<Runtime> start(
    Module module, {
    ResolverBackend? backend,
    CleanupFailureObserver? cleanupFailureObserver,
  }) async {
    final resolver = backend ?? AutoInjectorBackend();
    final rootScope = Scope._();
    final context = _RuntimeContext(
      backend: resolver,
      scope: rootScope,
      cancellation: CancellationSignal._(),
      overrides: const <_ServiceIdentity, Object>{},
      locals: const <Object, Object>{},
    );

    try {
      for (final binding in module) {
        if (!binding._isResource) {
          binding._register(resolver);
        }
      }

      resolver.commit();

      for (final binding in module) {
        if (binding._isResource) {
          await binding._startResource(context);
        }
      }

      await Future<void>.sync(resolver.activate);

      return Runtime._(context, cleanupFailureObserver);
    } catch (error, stackTrace) {
      final outcome = ExitDefect<Object, Object>(error, stackTrace);
      Object? cleanupError;
      StackTrace? cleanupStackTrace;

      try {
        await rootScope._close(outcome);
      } catch (releaseError, releaseStack) {
        await _notifyCleanupFailureBestEffort(
          cleanupFailureObserver,
          CleanupFailureDiagnostic(
            outcome: outcome,
            error: _asScopeReleaseException(releaseError, releaseStack),
            executionId: 0,
          ),
        );
        cleanupError = releaseError;
        cleanupStackTrace = releaseStack;
      }

      try {
        await Future<void>.sync(resolver.close);
      } catch (backendError, backendStackTrace) {
        if (cleanupError == null) {
          cleanupError = backendError;
          cleanupStackTrace = backendStackTrace;
        } else {
          cleanupError = CompositeDefect(
            primary: cleanupError,
            primaryStackTrace: cleanupStackTrace!,
            secondary: backendError,
            secondaryStackTrace: backendStackTrace,
          );
          cleanupStackTrace = backendStackTrace;
        }
      }

      if (cleanupError != null) {
        Error.throwWithStackTrace(
          CompositeDefect(
            primary: error,
            primaryStackTrace: stackTrace,
            secondary: cleanupError,
            secondaryStackTrace: cleanupStackTrace!,
          ),
          stackTrace,
        );
      }

      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Read-only access to the runtime's services at application boundaries.
  Services get services {
    _ensureActive();
    return Services._(_rootContext);
  }

  /// The current lifecycle state.
  RuntimeState get state => _state;

  /// Whether this Runtime no longer accepts new work.
  bool get isClosed => _state != RuntimeState.active;

  /// Start a managed Effect execution.
  EffectExecution<A, E> execute<A extends Object, E extends Object>(
    Effect<A, E> effect, {
    String? label,
  }) {
    _ensureActive();

    final execution = _EffectExecutionImpl<A, E>(
      id: ++_nextExecutionId,
      scope: _rootContext.scope._fork(),
      label: label,
    );
    _activeExecutions.add(execution);
    final context = _rootContext._withScope(
      execution.scope,
      cancellation: execution.cancellation,
    );

    unawaited(_runExecution(effect, context, execution));

    return execution;
  }

  /// Run an Effect and convert unexpected defects back into thrown errors.
  Future<ResultDart<A, E>> run<A extends Object, E extends Object>(
    Effect<A, E> effect, {
    String? executionLabel,
  }) async {
    final exit = await runExit(effect, executionLabel: executionLabel);
    return _resultFromExit(exit);
  }

  /// Run an Effect while preserving success, failure, and defects in [Exit].
  Future<Exit<A, E>> runExit<A extends Object, E extends Object>(
    Effect<A, E> effect, {
    String? executionLabel,
  }) {
    return execute(effect, label: executionLabel).exit;
  }

  Future<void> _runExecution<A extends Object, E extends Object>(
    Effect<A, E> effect,
    _RuntimeContext context,
    _EffectExecutionImpl<A, E> execution,
  ) async {
    try {
      Exit<A, E> computedExit;

      try {
        final result = await effect._run(context);
        computedExit = result.fold<Exit<A, E>>(
          (value) => ExitSuccess<A, E>(value),
          (error) => ExitFailure<A, E>(error),
        );
      } on _CancellationRequested {
        computedExit = ExitInterrupted<A, E>();
      } catch (error, stackTrace) {
        computedExit = ExitDefect<A, E>(error, stackTrace);
      }

      final wasPublished = execution.hasPublishedExit;
      final outcome = execution.publishedExit ?? computedExit;

      if (wasPublished && computedExit is ExitDefect<A, E>) {
        _recordDeferredExecutionFailure(
          computedExit.defect,
          computedExit.stackTrace,
        );
      }

      if (execution.scope._hasPendingPhysical || wasPublished) {
        if (!wasPublished) {
          execution.completeLogical(computedExit);
        }

        try {
          await execution.scope._close(outcome);
        } catch (error, stackTrace) {
          await _reportCleanupFailure(
            _asScopeReleaseException(error, stackTrace),
            outcome,
            execution: execution,
          );
          _recordDeferredExecutionFailure(error, stackTrace);
        }
      } else {
        final closedExit = await _closeExecutionScope(
          execution.scope,
          outcome,
          execution,
        );
        execution.completeLogical(closedExit);
      }
    } catch (error, stackTrace) {
      if (execution.hasPublishedExit) {
        _recordDeferredExecutionFailure(error, stackTrace);
      } else {
        execution.completeLogicalError(error, stackTrace);
      }
    } finally {
      _activeExecutions.remove(execution);
      execution.completePhysical();
    }
  }

  Future<Exit<A, E>> _closeExecutionScope<A extends Object, E extends Object>(
    Scope scope,
    Exit<A, E> exit,
    _RuntimeExecution execution,
  ) async {
    try {
      await scope._close(exit);
      return exit;
    } catch (releaseError, releaseStackTrace) {
      await _reportCleanupFailure(
        _asScopeReleaseException(releaseError, releaseStackTrace),
        exit,
        execution: execution,
      );

      if (exit is ExitSuccess<A, E>) {
        return ExitDefect<A, E>(releaseError, releaseStackTrace);
      }

      if (exit is ExitDefect<A, E>) {
        return ExitDefect<A, E>(
          CompositeDefect(
            primary: exit.defect,
            primaryStackTrace: exit.stackTrace,
            secondary: releaseError,
            secondaryStackTrace: releaseStackTrace,
          ),
          exit.stackTrace,
        );
      }

      return exit;
    }
  }

  Future<void> _reportCleanupFailure(
    ScopeReleaseException error,
    Exit<Object, Object> outcome, {
    required _RuntimeExecution execution,
  }) {
    return _notifyCleanupFailureBestEffort(
      _cleanupFailureObserver,
      CleanupFailureDiagnostic(
        outcome: outcome,
        error: error,
        executionId: execution.id,
        executionLabel: execution.label,
      ),
    );
  }

  void _recordDeferredExecutionFailure(Object error, StackTrace stackTrace) {
    _deferredExecutionFailures.add((error: error, stackTrace: stackTrace));
  }

  /// Close this runtime and release module-owned resources.
  ///
  /// Active executions are always awaited. When [interruptAfterGracePeriod]
  /// is true, [gracePeriod] requests cooperative cancellation before waiting
  /// for those executions to finish.
  Future<void> close({
    Duration gracePeriod = Duration.zero,
    bool interruptAfterGracePeriod = false,
  }) {
    if (gracePeriod.isNegative) {
      throw ArgumentError.value(
        gracePeriod,
        'gracePeriod',
        'must not be negative',
      );
    }

    return _closeWith(
      const ExitInterrupted<Object, Object>(),
      gracePeriod: gracePeriod,
      interruptAfterGracePeriod: interruptAfterGracePeriod,
    );
  }

  Future<void> _closeWith(
    Exit<Object, Object> exit, {
    Duration gracePeriod = Duration.zero,
    bool interruptAfterGracePeriod = false,
  }) {
    if (_state == RuntimeState.closed) {
      return Future<void>.value();
    }

    final closingFuture = _closingFuture;
    if (closingFuture != null) {
      return closingFuture;
    }

    _state = RuntimeState.closing;
    final future = _finishClose(
      exit,
      gracePeriod: gracePeriod,
      interruptAfterGracePeriod: interruptAfterGracePeriod,
    );
    _closingFuture = future;
    return future;
  }

  Future<void> _finishClose(
    Exit<Object, Object> exit, {
    required Duration gracePeriod,
    required bool interruptAfterGracePeriod,
  }) async {
    Object? closeError;
    StackTrace? closeStackTrace;

    void captureError(Object error, StackTrace stackTrace) {
      if (closeError == null) {
        closeError = error;
        closeStackTrace = stackTrace;
        return;
      }

      closeError = CompositeDefect(
        primary: closeError!,
        primaryStackTrace: closeStackTrace!,
        secondary: error,
        secondaryStackTrace: stackTrace,
      );
    }

    try {
      await _awaitActiveExecutions(
        gracePeriod: gracePeriod,
        interruptAfterGracePeriod: interruptAfterGracePeriod,
      );
    } catch (error, stackTrace) {
      captureError(error, stackTrace);
    }

    if (_deferredExecutionFailures.isNotEmpty) {
      final failures = List<ReleaseFailure>.of(_deferredExecutionFailures);
      _deferredExecutionFailures.clear();
      captureError(ScopeReleaseException(failures), failures.first.stackTrace);
    }

    try {
      await _rootContext.scope._close(exit);
    } catch (error, stackTrace) {
      await _notifyCleanupFailureBestEffort(
        _cleanupFailureObserver,
        CleanupFailureDiagnostic(
          outcome: exit,
          error: _asScopeReleaseException(error, stackTrace),
          executionId: 0,
        ),
      );
      captureError(error, stackTrace);
    }

    try {
      await Future<void>.sync(_rootContext.backend.close);
    } catch (error, stackTrace) {
      captureError(error, stackTrace);
    }

    _state = RuntimeState.closed;

    final error = closeError;
    if (error != null) {
      Error.throwWithStackTrace(error, closeStackTrace!);
    }
  }

  Future<void> _awaitActiveExecutions({
    required Duration gracePeriod,
    required bool interruptAfterGracePeriod,
  }) async {
    final executions = List<_RuntimeExecution>.of(_activeExecutions);
    if (executions.isEmpty) {
      return;
    }

    final allCompleted = Future.wait<void>(
      executions.map((execution) => execution.completed),
    );

    if (interruptAfterGracePeriod) {
      await Future.any<void>(<Future<void>>[
        allCompleted,
        Future<void>.delayed(gracePeriod),
      ]);

      for (final execution in executions) {
        if (!execution.isCompleted) {
          execution.requestInterruption('runtime-shutdown');
        }
      }
    }

    await allCompleted;
  }

  void _ensureActive() {
    if (_state != RuntimeState.active) {
      throw const RuntimeClosedException();
    }
  }
}

ScopeReleaseException _asScopeReleaseException(
  Object error,
  StackTrace stackTrace,
) {
  if (error is ScopeReleaseException) {
    return error;
  }

  return ScopeReleaseException(<ReleaseFailure>[
    (error: error, stackTrace: stackTrace),
  ]);
}

Future<void> _notifyCleanupFailureBestEffort(
  CleanupFailureObserver? observer,
  CleanupFailureDiagnostic diagnostic,
) async {
  if (observer == null) {
    return;
  }

  try {
    await Future<void>.sync(() => observer(diagnostic));
  } catch (_) {
    // Observers are diagnostics only and must not affect the Effect outcome.
  }
}
