part of '../../better_effect_flutter.dart';

/// Observes every visible state published by one command.
typedef EffectCommandStateObserver<A extends Object, E extends Object> =
    void Function(EffectCommandState<A, E> state);

/// An Effect command with one typed input.
///
/// Multiple logical arguments can be represented by a named record, avoiding
/// arity-specific `Command2`, `Command3`, and similar types.
final class EffectCommand<I, A extends Object, E extends Object>
    extends EffectCommandBase<A, E> {
  EffectCommand._(
    Runtime runtime,
    this._action, {
    required EffectCommandConcurrency concurrency,
    required bool keepPreviousData,
    required String? debugLabel,
    required VoidCallback? onCancel,
    required EffectCommandStateObserver<A, E>? stateObserver,
    required EffectCommandObserver? transitionObserver,
  }) : super._(
         runtime,
         concurrency: concurrency,
         keepPreviousData: keepPreviousData,
         debugLabel: debugLabel,
         onCancel: onCancel,
         stateObserver: stateObserver,
         transitionObserver: transitionObserver,
       );

  final Effect<A, E> Function(I input) _action;
  late I _lastInput;
  bool _hasLastInput = false;

  bool get canRetry => _hasLastInput;

  I? get lastInputOrNull => _hasLastInput ? _lastInput : null;

  /// Callable-object shorthand for [execute].
  Future<Exit<A, E>> call(I input) => execute(input);

  Future<Exit<A, E>> execute(I input) {
    final dropped =
        concurrency == EffectCommandConcurrency.drop &&
        _activeCompleter != null;
    final execution = _executeEffect(() => _action(input));

    if (!dropped) {
      _lastInput = input;
      _hasLastInput = true;
    }

    return execution;
  }

  Future<Exit<A, E>> retry() {
    if (!_hasLastInput) {
      throw StateError(
        '${debugLabel ?? runtimeType} cannot retry before its first execution.',
      );
    }

    return execute(_lastInput);
  }
}

/// An Effect command without input parameters.
final class EffectCommand0<A extends Object, E extends Object>
    extends EffectCommandBase<A, E> {
  EffectCommand0._(
    Runtime runtime,
    this._action, {
    required EffectCommandConcurrency concurrency,
    required bool keepPreviousData,
    required String? debugLabel,
    required VoidCallback? onCancel,
    required EffectCommandStateObserver<A, E>? stateObserver,
    required EffectCommandObserver? transitionObserver,
  }) : super._(
         runtime,
         concurrency: concurrency,
         keepPreviousData: keepPreviousData,
         debugLabel: debugLabel,
         onCancel: onCancel,
         stateObserver: stateObserver,
         transitionObserver: transitionObserver,
       );

  final Effect<A, E> Function() _action;

  /// Callable-object shorthand for [execute].
  Future<Exit<A, E>> call() => execute();

  Future<Exit<A, E>> execute() => _executeEffect(_action);

  Future<Exit<A, E>> retry() => execute();
}

/// A Flutter-facing command that executes typed [Effect] values through a
/// long-lived [Runtime].
///
/// Commands are [ValueListenable] objects. ViewModels own them and Views observe
/// them through [EffectCommandBuilder], [EffectCommandListener], or Flutter's
/// standard `Listenable` APIs.
sealed class EffectCommandBase<A extends Object, E extends Object>
    extends ChangeNotifier
    implements
        ValueListenable<EffectCommandState<A, E>>,
        EffectCommandDisposable {
  EffectCommandBase._(
    this._runtime, {
    required this.concurrency,
    required this.keepPreviousData,
    required this.debugLabel,
    required this.onCancel,
    required EffectCommandStateObserver<A, E>? stateObserver,
    required EffectCommandObserver? transitionObserver,
  }) : _stateObserver = stateObserver,
       _transitionObserver = transitionObserver,
       _value = EffectCommandIdle<A, E>._(
         revision: 0,
         executionId: 0,
         previous: null,
       );

  final Runtime _runtime;
  final EffectCommandStateObserver<A, E>? _stateObserver;
  final EffectCommandObserver? _transitionObserver;
  final Queue<_QueuedEffectExecution<A, E>> _queue =
      Queue<_QueuedEffectExecution<A, E>>();
  final Map<int, Completer<Exit<A, E>>> _pendingCompletions =
      <int, Completer<Exit<A, E>>>{};

  /// How repeated executions are coordinated.
  final EffectCommandConcurrency concurrency;

  /// Whether running/failure/defect/interrupted states retain the latest data.
  final bool keepPreviousData;

  /// Optional diagnostic name included in global transitions and error reports.
  final String? debugLabel;

  /// Optional cooperative cancellation hook.
  ///
  /// Use this to signal a token owned by Dio, an isolate, a download manager, or
  /// another cancellable API. An arbitrary Dart Future cannot be forcefully
  /// cancelled by the command itself.
  final VoidCallback? onCancel;

  EffectCommandState<A, E> _value;
  Future<Exit<A, E>>? _inFlight;
  Completer<Exit<A, E>>? _activeCompleter;

  int _revision = 0;
  int _nextExecutionId = 0;
  int? _activeExecutionId;

  A? _lastSuccess;
  E? _lastFailure;
  Exit<A, E>? _lastExit;
  bool _disposed = false;

  /// Current successful data, including retained previous data.
  A? get data => _value.dataOrNull;

  /// Current typed failure.
  E? get error => _value.errorOrNull;

  @override
  bool get isDisposed => _disposed;

  bool get isRunning => _value.isRunning;

  Object? get lastDefect => switch (_lastExit) {
    ExitDefect<A, E>(:final defect) => defect,
    _ => null,
  };

  StackTrace? get lastDefectStackTrace => switch (_lastExit) {
    ExitDefect<A, E>(:final stackTrace) => stackTrace,
    _ => null,
  };

  /// Latest authoritative execution outcome.
  Exit<A, E>? get lastExit => _lastExit;

  /// Latest typed failure, even after a later success.
  E? get lastFailure => _lastFailure;

  /// Latest successful value, even after a later failure.
  A? get lastSuccess => _lastSuccess;

  /// Executions still running in Dart plus queued execution count.
  ///
  /// With [EffectCommandConcurrency.latest], this can be greater than one even
  /// after the newest execution has already produced visible state, because
  /// stale Futures are allowed to finish without overwriting that state.
  int get pendingCount => _pendingCompletions.length + _queue.length;

  /// Number of executions waiting behind the authoritative execution.
  int get queuedCount => _queue.length;

  /// Latest success/failure as Result. Defects and interruption return null.
  ResultDart<A, E>? get resultOrNull => switch (_lastExit) {
    ExitSuccess<A, E>(:final value) => Success<A, E>(value),
    ExitFailure<A, E>(:final error) => Failure<A, E>(error),
    _ => null,
  };

  @override
  EffectCommandState<A, E> get value => _value;

  A? get _retainedData => keepPreviousData ? _lastSuccess : null;

  /// Interrupt ownership of the current execution.
  ///
  /// Returns false when no authoritative execution is active. The underlying
  /// Future is not forcefully stopped; [onCancel] can perform cooperative
  /// cancellation. Its eventual completion is ignored by this command, while
  /// the Future returned by [EffectCommand0.execute] or [EffectCommand.execute]
  /// completes with [ExitInterrupted].
  ///
  /// When [clearQueued] is true, queued executions complete as interrupted
  /// without starting. When false, the next queued operation starts immediately.
  bool cancel({bool clearQueued = true}) {
    _ensureNotDisposed();

    final executionId = _activeExecutionId;
    if (!_value.isRunning || executionId == null || _inFlight == null) {
      if (clearQueued) {
        _interruptQueued();
      }
      return false;
    }

    final completion = _activeCompleter;

    _activeExecutionId = null;
    _inFlight = null;
    _activeCompleter = null;
    _pendingCompletions.remove(executionId);

    try {
      onCancel?.call();
    } catch (error, stackTrace) {
      final defect = ExitDefect<A, E>(error, stackTrace);
      _lastExit = defect;
      if (completion != null && !completion.isCompleted) {
        completion.complete(defect);
      }
      _setState(
        EffectCommandDefect<A, E>._(
          revision: _nextRevision(),
          executionId: executionId,
          defect: error,
          stackTrace: stackTrace,
          completedAt: DateTime.now(),
          previous: _retainedData,
        ),
      );

      if (clearQueued) {
        _interruptQueued();
      } else {
        _startNextQueuedIfPossible();
      }
      return true;
    }

    final interrupted = ExitInterrupted<A, E>();
    _lastExit = interrupted;
    if (completion != null && !completion.isCompleted) {
      completion.complete(interrupted);
    }
    _setState(
      EffectCommandInterrupted<A, E>._(
        revision: _nextRevision(),
        executionId: executionId,
        interruptedAt: DateTime.now(),
        previous: _retainedData,
      ),
    );

    if (clearQueued) {
      _interruptQueued();
    } else {
      _startNextQueuedIfPossible();
    }

    return true;
  }

  /// Clear state and cached values after work finishes.
  bool clear() => reset(clearCache: true);

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    final hadActiveExecution = _activeExecutionId != null && _inFlight != null;

    _disposed = true;
    _activeExecutionId = null;
    _inFlight = null;
    _activeCompleter = null;

    for (final completion in _pendingCompletions.values) {
      if (!completion.isCompleted) {
        completion.complete(ExitInterrupted<A, E>());
      }
    }
    _pendingCompletions.clear();

    _interruptQueued();

    if (hadActiveExecution) {
      try {
        onCancel?.call();
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'better_effect_flutter',
            context: ErrorDescription(
              'while disposing ${debugLabel ?? runtimeType}',
            ),
          ),
        );
      }
    }

    super.dispose();
  }

  /// Return to idle after work finishes.
  ///
  /// Returns false while an authoritative or queued execution exists. Set
  /// [clearCache] to remove remembered success and failure values.
  bool reset({bool clearCache = false}) {
    _ensureNotDisposed();

    if (_inFlight != null || _queue.isNotEmpty) {
      return false;
    }

    if (clearCache) {
      _lastSuccess = null;
      _lastFailure = null;
    }

    _lastExit = null;
    _activeExecutionId = null;

    _setState(
      EffectCommandIdle<A, E>._(
        revision: _nextRevision(),
        executionId: 0,
        previous: _retainedData,
      ),
    );

    return true;
  }

  @override
  String toString() {
    final label = debugLabel == null ? '' : ' "$debugLabel"';
    return '$runtimeType$label($_value)';
  }

  Future<Exit<A, E>> _enqueue(Effect<A, E> Function() createEffect) {
    final queued = _QueuedEffectExecution<A, E>(createEffect);
    _queue.addLast(queued);
    return queued.completer.future;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError(
        '${debugLabel ?? runtimeType} was used after it was disposed.',
      );
    }
  }

  Future<Exit<A, E>> _executeEffect(Effect<A, E> Function() createEffect) {
    _ensureNotDisposed();

    final current = _activeCompleter;
    if (current == null) {
      return _startExecution(createEffect);
    }

    return switch (concurrency) {
      EffectCommandConcurrency.drop => current.future,
      EffectCommandConcurrency.latest => _startExecution(createEffect),
      EffectCommandConcurrency.queue => _enqueue(createEffect),
    };
  }

  void _interruptQueued() {
    while (_queue.isNotEmpty) {
      final queued = _queue.removeFirst();
      if (!queued.completer.isCompleted) {
        queued.completer.complete(ExitInterrupted<A, E>());
      }
    }
  }

  int _nextRevision() => ++_revision;

  bool _owns(int executionId) =>
      !_disposed && _activeExecutionId == executionId;

  void _reportObserverError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'better_effect_flutter',
        context: ErrorDescription(
          'while observing ${debugLabel ?? runtimeType}',
        ),
      ),
    );
  }

  Future<Exit<A, E>> _runEffect(
    Effect<A, E> Function() createEffect,
    int executionId,
  ) async {
    Exit<A, E> exit;

    try {
      exit = await _runtime.runExit(createEffect());
    } catch (error, stackTrace) {
      exit = ExitDefect<A, E>(error, stackTrace);
    }

    // `latest`, interruption, and disposal can revoke ownership while the Dart
    // Future continues. Callers still receive the Exit, but stale work cannot
    // overwrite the command's visible state.
    if (!_owns(executionId)) {
      return exit;
    }

    _lastExit = exit;
    final completedAt = DateTime.now();

    switch (exit) {
      case ExitSuccess<A, E>(:final value):
        _lastSuccess = value;
        _setState(
          EffectCommandSuccess<A, E>._(
            revision: _nextRevision(),
            executionId: executionId,
            value: value,
            completedAt: completedAt,
          ),
        );

      case ExitFailure<A, E>(:final error):
        _lastFailure = error;
        _setState(
          EffectCommandFailure<A, E>._(
            revision: _nextRevision(),
            executionId: executionId,
            error: error,
            completedAt: completedAt,
            previous: _retainedData,
          ),
        );

      case ExitDefect<A, E>(:final defect, :final stackTrace):
        _setState(
          EffectCommandDefect<A, E>._(
            revision: _nextRevision(),
            executionId: executionId,
            defect: defect,
            stackTrace: stackTrace,
            completedAt: completedAt,
            previous: _retainedData,
          ),
        );

      case ExitInterrupted<A, E>():
        _setState(
          EffectCommandInterrupted<A, E>._(
            revision: _nextRevision(),
            executionId: executionId,
            interruptedAt: completedAt,
            previous: _retainedData,
          ),
        );
    }

    return exit;
  }

  void _setState(EffectCommandState<A, E> state) {
    if (_disposed) {
      return;
    }

    final previous = _value;
    _value = state;
    notifyListeners();

    final stateObserver = _stateObserver;
    if (stateObserver != null) {
      try {
        stateObserver(state);
      } catch (error, stackTrace) {
        _reportObserverError(error, stackTrace);
      }
    }

    final transitionObserver = _transitionObserver;
    if (transitionObserver != null) {
      try {
        transitionObserver(
          EffectCommandTransition(
            previous: previous,
            current: state,
            timestamp: DateTime.now(),
            debugLabel: debugLabel,
          ),
        );
      } catch (error, stackTrace) {
        _reportObserverError(error, stackTrace);
      }
    }
  }

  Future<Exit<A, E>> _startExecution(
    Effect<A, E> Function() createEffect, {
    Completer<Exit<A, E>>? queuedCompleter,
  }) {
    final executionId = ++_nextExecutionId;
    final completion = queuedCompleter ?? Completer<Exit<A, E>>();

    _activeExecutionId = executionId;
    _activeCompleter = completion;
    _pendingCompletions[executionId] = completion;

    _setState(
      EffectCommandRunning<A, E>._(
        revision: _nextRevision(),
        executionId: executionId,
        startedAt: DateTime.now(),
        previous: _retainedData,
      ),
    );

    final tracked = _trackExecution(createEffect, executionId, completion);
    _inFlight = tracked;

    return completion.future;
  }

  void _startNextQueuedIfPossible() {
    if (_disposed ||
        concurrency != EffectCommandConcurrency.queue ||
        _queue.isEmpty) {
      return;
    }

    final next = _queue.removeFirst();
    _startExecution(next.createEffect, queuedCompleter: next.completer);
  }

  Future<Exit<A, E>> _trackExecution(
    Effect<A, E> Function() createEffect,
    int executionId,
    Completer<Exit<A, E>> completion,
  ) async {
    try {
      final exit = await _runEffect(createEffect, executionId);

      if (!completion.isCompleted) {
        completion.complete(exit);
      }

      return exit;
    } catch (error, stackTrace) {
      if (!completion.isCompleted) {
        completion.completeError(error, stackTrace);
      }

      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _pendingCompletions.remove(executionId);

      if (!_disposed && _activeExecutionId == executionId) {
        _inFlight = null;
        _activeCompleter = null;
        _activeExecutionId = null;
        _startNextQueuedIfPossible();
      }
    }
  }
}

/// The minimal lifecycle contract shared by all Effect command variants.
abstract interface class EffectCommandDisposable {
  bool get isDisposed;

  void dispose();
}

final class _QueuedEffectExecution<A extends Object, E extends Object> {
  _QueuedEffectExecution(this.createEffect)
    : completer = Completer<Exit<A, E>>();

  final Effect<A, E> Function() createEffect;
  final Completer<Exit<A, E>> completer;
}
