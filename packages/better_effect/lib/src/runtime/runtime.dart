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

/// A cooperative cancellation signal exposed to an active Effect.
///
/// A signal request does not cancel arbitrary Dart Futures. Code using a
/// cancellable API can observe [isCancelled] or await [whenCancelled].
final class CancellationSignal {
  CancellationSignal._();

  final Completer<void> _whenCancelled = Completer<void>.sync();
  bool _isCancelled = false;

  /// Whether cancellation has been requested.
  bool get isCancelled => _isCancelled;

  /// Completes when cancellation is requested.
  Future<void> get whenCancelled => _whenCancelled.future;

  void _cancel() {
    if (_isCancelled) {
      return;
    }

    _isCancelled = true;
    _whenCancelled.complete();
  }
}

final class _ActiveExecution {
  _ActiveExecution(this.scope) : cancellation = CancellationSignal._();

  final Scope scope;
  final CancellationSignal cancellation;
  final Completer<void> _completed = Completer<void>.sync();

  Future<void> get completed => _completed.future;

  bool get isCompleted => _completed.isCompleted;

  void interrupt() => cancellation._cancel();

  void complete() {
    if (!_completed.isCompleted) {
      _completed.complete();
    }
  }
}

/// Executes Effects against the environment built from a [Module].
final class Runtime {
  Runtime._(this._rootContext);

  final _RuntimeContext _rootContext;
  // ponytail: tracks awaited execution Futures; detached child Futures need
  // explicit cancellation or lease tracking if that ceiling becomes a bug.
  final Set<_ActiveExecution> _activeExecutions = <_ActiveExecution>{};
  final List<ReleaseFailure> _deferredExecutionFailures = <ReleaseFailure>[];
  RuntimeState _state = RuntimeState.active;
  Future<void>? _closingFuture;

  /// Build a runtime, install constructor bindings, and acquire resources.
  static Future<Runtime> start(
    Module module, {
    ResolverBackend? backend,
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

      return Runtime._(context);
    } catch (error, stackTrace) {
      Object? cleanupError;
      StackTrace? cleanupStackTrace;

      try {
        await rootScope._close(ExitDefect<Object, Object>(error, stackTrace));
      } catch (releaseError, releaseStack) {
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

  /// Run an Effect and convert unexpected defects back into thrown errors.
  Future<ResultDart<A, E>> run<A extends Object, E extends Object>(
    Effect<A, E> effect,
  ) async {
    final exit = await runExit(effect);
    return _resultFromExit(exit);
  }

  /// Run an Effect while preserving success, failure, and defects in [Exit].
  Future<Exit<A, E>> runExit<A extends Object, E extends Object>(
    Effect<A, E> effect,
  ) {
    _ensureActive();

    final execution = _ActiveExecution(_rootContext.scope._fork());
    _activeExecutions.add(execution);
    final context = _rootContext._withScope(
      execution.scope,
      cancellation: execution.cancellation,
    );
    final logicalExit = Completer<Exit<A, E>>.sync();

    unawaited(_runExecution(effect, context, execution, logicalExit));

    return logicalExit.future;
  }

  Future<void> _runExecution<A extends Object, E extends Object>(
    Effect<A, E> effect,
    _RuntimeContext context,
    _ActiveExecution execution,
    Completer<Exit<A, E>> logicalExit,
  ) async {
    try {
      Exit<A, E> exit;

      try {
        final result = await effect._run(context);
        exit = result.fold<Exit<A, E>>(
          (value) => ExitSuccess<A, E>(value),
          (error) => ExitFailure<A, E>(error),
        );
      } catch (error, stackTrace) {
        exit = ExitDefect<A, E>(error, stackTrace);
      }

      if (execution.scope._hasPendingPhysical) {
        // Deliver the logical result now; Scope._close waits for the physical
        // operation before releasing execution resources.
        logicalExit.complete(exit);

        try {
          await execution.scope._close(exit);
        } catch (error, stackTrace) {
          _recordDeferredExecutionFailure(error, stackTrace);
        }
      } else {
        logicalExit.complete(await _closeExecutionScope(execution.scope, exit));
      }
    } catch (error, stackTrace) {
      if (logicalExit.isCompleted) {
        _recordDeferredExecutionFailure(error, stackTrace);
      } else {
        logicalExit.completeError(error, stackTrace);
      }
    } finally {
      _activeExecutions.remove(execution);
      execution.complete();
    }
  }

  Future<Exit<A, E>> _closeExecutionScope<A extends Object, E extends Object>(
    Scope scope,
    Exit<A, E> exit,
  ) async {
    try {
      await scope._close(exit);
      return exit;
    } catch (releaseError, releaseStackTrace) {
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

      return ExitDefect<A, E>(releaseError, releaseStackTrace);
    }
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
    final executions = List<_ActiveExecution>.of(_activeExecutions);
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
          execution.interrupt();
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
