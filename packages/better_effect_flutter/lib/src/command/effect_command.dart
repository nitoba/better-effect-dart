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
    required CommandPolicy policy,
    required bool keepPreviousData,
    required String? debugLabel,
    required VoidCallback? onCancel,
    required EffectCommandStateObserver<A, E>? stateObserver,
    required EffectCommandObserver? transitionObserver,
    required EffectCommandPolicyObserver? sharedPolicyObserver,
    required EffectCommandPolicyObserver? policyObserver,
  }) : super._(
         runtime,
         policy: policy,
         keepPreviousData: keepPreviousData,
         debugLabel: debugLabel,
         onCancel: onCancel,
         stateObserver: stateObserver,
         transitionObserver: transitionObserver,
         sharedPolicyObserver: sharedPolicyObserver,
         policyObserver: policyObserver,
       );

  final Effect<A, E> Function(I input) _action;
  late I _lastInput;
  bool _hasLastInput = false;

  bool get canRetry => _hasLastInput;

  I? get lastInputOrNull => _hasLastInput ? _lastInput : null;

  /// Callable-object shorthand for [execute].
  Future<Exit<A, E>> call(I input) => execute(input);

  Future<Exit<A, E>> execute(I input) {
    final submission = _submitEffect(() => _action(input));
    if (submission.rememberInput) {
      _lastInput = input;
      _hasLastInput = true;
    }
    return submission.future;
  }

  /// Submit the latest accepted input through the same policy again.
  ///
  /// Retry is an ordinary invocation. It can therefore be coalesced, queued,
  /// debounced, throttled, or rejected by the configured policy.
  Future<Exit<A, E>> retry() {
    if (!_hasLastInput) {
      throw StateError(
        '${debugLabel ?? runtimeType} cannot retry before its first accepted '
        'input.',
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
    required CommandPolicy policy,
    required bool keepPreviousData,
    required String? debugLabel,
    required VoidCallback? onCancel,
    required EffectCommandStateObserver<A, E>? stateObserver,
    required EffectCommandObserver? transitionObserver,
    required EffectCommandPolicyObserver? sharedPolicyObserver,
    required EffectCommandPolicyObserver? policyObserver,
  }) : super._(
         runtime,
         policy: policy,
         keepPreviousData: keepPreviousData,
         debugLabel: debugLabel,
         onCancel: onCancel,
         stateObserver: stateObserver,
         transitionObserver: transitionObserver,
         sharedPolicyObserver: sharedPolicyObserver,
         policyObserver: policyObserver,
       );

  final Effect<A, E> Function() _action;

  /// Callable-object shorthand for [execute].
  Future<Exit<A, E>> call() => execute();

  Future<Exit<A, E>> execute() => _submitEffect(_action).future;

  Future<Exit<A, E>> retry() => execute();
}

/// A Flutter-facing command that executes typed [Effect] values through a
/// long-lived [Runtime].
sealed class EffectCommandBase<A extends Object, E extends Object>
    extends ChangeNotifier
    implements
        ValueListenable<EffectCommandState<A, E>>,
        EffectCommandDisposable {
  EffectCommandBase._(
    this._runtime, {
    required this.policy,
    required this.keepPreviousData,
    required this.debugLabel,
    required this.onCancel,
    required EffectCommandStateObserver<A, E>? stateObserver,
    required EffectCommandObserver? transitionObserver,
    required EffectCommandPolicyObserver? sharedPolicyObserver,
    required EffectCommandPolicyObserver? policyObserver,
  }) : _stateObserver = stateObserver,
       _transitionObserver = transitionObserver,
       _sharedPolicyObserver = sharedPolicyObserver,
       _policyObserver = policyObserver,
       _value = EffectCommandIdle<A, E>._(
         revision: 0,
         executionId: 0,
         previous: null,
       );

  final Runtime _runtime;
  final EffectCommandStateObserver<A, E>? _stateObserver;
  final EffectCommandObserver? _transitionObserver;
  final EffectCommandPolicyObserver? _sharedPolicyObserver;
  final EffectCommandPolicyObserver? _policyObserver;
  final Queue<_QueuedEffectExecution<A, E>> _queue =
      Queue<_QueuedEffectExecution<A, E>>();
  final Map<int, Completer<Exit<A, E>>> _pendingCompletions =
      <int, Completer<Exit<A, E>>>{};
  final Map<int, EffectExecution<A, E>> _runtimeExecutions =
      <int, EffectExecution<A, E>>{};

  /// Immutable execution and trigger policy.
  final CommandPolicy policy;

  /// Compatibility projection for code that still reads the original enum.
  EffectCommandConcurrency get concurrency => policy._legacyConcurrency;

  /// Whether running/failure/defect/interrupted states retain the latest data.
  final bool keepPreviousData;

  /// Optional diagnostic name included in state transitions, policy events, and
  /// Runtime execution metadata.
  final String? debugLabel;

  /// Optional adapter hook invoked after core interruption is requested.
  final VoidCallback? onCancel;

  EffectCommandState<A, E> _value;
  Future<Exit<A, E>>? _inFlight;
  Completer<Exit<A, E>>? _activeCompleter;
  EffectExecution<A, E>? _activeRuntimeExecution;

  _TriggeredEffectExecution<A, E>? _pendingTrigger;
  EffectExecution<_CommandTriggerToken, Never>? _triggerExecution;
  EffectClock? _triggerClock;
  bool _triggerWindowOpen = false;
  int _triggerGeneration = 0;

  int _revision = 0;
  int _nextExecutionId = 0;
  int _nextInvocationId = 0;
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

  /// Caller-visible executions that have not completed, queued callers, and a
  /// trailing debounce/throttle caller waiting for its trigger window.
  int get pendingCount {
    return _pendingCompletions.length +
        _queue.length +
        (_pendingTrigger == null ? 0 : 1);
  }

  /// Number of executions waiting behind the authoritative queue execution.
  int get queuedCount => _queue.length;

  /// Whether a debounce/throttle trailing invocation is currently waiting.
  int get triggerPendingCount => _pendingTrigger == null ? 0 : 1;

  /// Latest success/failure as Result. Defects and interruption return null.
  ResultDart<A, E>? get resultOrNull => switch (_lastExit) {
    ExitSuccess<A, E>(:final value) => Success<A, E>(value),
    ExitFailure<A, E>(:final error) => Failure<A, E>(error),
    _ => null,
  };

  @override
  EffectCommandState<A, E> get value => _value;

  A? get _retainedData => keepPreviousData ? _lastSuccess : null;

  /// Interrupt current ownership and optionally clear policy-pending callers.
  ///
  /// With [clearQueued] true, queued and trigger-delayed callers complete with
  /// [ExitInterrupted], and an active debounce/throttle window is cancelled.
  bool cancel({bool clearQueued = true}) {
    _ensureNotDisposed();

    var changed = false;
    if (clearQueued) {
      changed =
          _interruptQueued(CommandPolicyReason.commandCancelled) || changed;
      changed =
          _interruptPendingTrigger(CommandPolicyReason.commandCancelled) ||
          changed;
      changed =
          _cancelTriggerWindow(CommandPolicyReason.commandCancelled) || changed;
    }

    final executionId = _activeExecutionId;
    if (!_value.isRunning || executionId == null || _inFlight == null) {
      return changed;
    }

    final completion = _activeCompleter;
    final runtimeExecution =
        _activeRuntimeExecution ?? _runtimeExecutions[executionId];

    _activeExecutionId = null;
    _inFlight = null;
    _activeCompleter = null;
    _activeRuntimeExecution = null;
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
      runtimeExecution?.interrupt(reason: 'command-cancelled');
      _emitPolicyEvent(
        decision: CommandPolicyDecision.cancelled,
        invocationId: 0,
        executionId: executionId,
        reason: CommandPolicyReason.commandCancelled,
      );

      if (!clearQueued) {
        _startNextQueuedIfPossible();
      }
      return true;
    }

    runtimeExecution?.interrupt(reason: 'command-cancelled');
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
    _emitPolicyEvent(
      decision: CommandPolicyDecision.cancelled,
      invocationId: 0,
      executionId: executionId,
      reason: CommandPolicyReason.commandCancelled,
    );

    if (!clearQueued) {
      _startNextQueuedIfPossible();
    }

    return true;
  }

  /// Clear state and cached values after all work and policy timers finish.
  bool clear() => reset(clearCache: true);

  @override
  void dispose() {
    if (_disposed) return;

    final hadActiveExecution = _activeExecutionId != null && _inFlight != null;
    _disposed = true;

    _cancelTriggerWindow(CommandPolicyReason.commandDisposed);
    _interruptPendingTrigger(CommandPolicyReason.commandDisposed);
    _interruptQueued(CommandPolicyReason.commandDisposed);

    for (final execution in List<EffectExecution<A, E>>.of(
      _runtimeExecutions.values,
    )) {
      execution.interrupt(reason: 'command-disposed');
    }
    _runtimeExecutions.clear();

    for (final completion in _pendingCompletions.values) {
      if (!completion.isCompleted) {
        completion.complete(ExitInterrupted<A, E>());
      }
    }
    _pendingCompletions.clear();

    _activeExecutionId = null;
    _inFlight = null;
    _activeCompleter = null;
    _activeRuntimeExecution = null;

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

  /// Return to idle after work and policy timing finish.
  ///
  /// Returns false while an authoritative, queued, or trigger-delayed invocation
  /// exists, or while a debounce/throttle window is still active.
  bool reset({bool clearCache = false}) {
    _ensureNotDisposed();

    if (_inFlight != null ||
        _queue.isNotEmpty ||
        _pendingTrigger != null ||
        _triggerExecution != null ||
        _triggerWindowOpen) {
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
    return '$runtimeType$label(policy: $policy, state: $_value)';
  }

  _CommandSubmission<A, E> _submitEffect(Effect<A, E> Function() createEffect) {
    _ensureNotDisposed();
    final invocationId = ++_nextInvocationId;

    return switch (policy.trigger.kind) {
      TriggerPolicyKind.immediate => _coordinateInvocation(
        createEffect,
        invocationId: invocationId,
      ),
      TriggerPolicyKind.debounce => _submitDebounced(
        createEffect,
        invocationId: invocationId,
      ),
      TriggerPolicyKind.throttle => _submitThrottled(
        createEffect,
        invocationId: invocationId,
      ),
    };
  }

  _CommandSubmission<A, E> _coordinateInvocation(
    Effect<A, E> Function() createEffect, {
    required int invocationId,
    Completer<Exit<A, E>>? callerCompleter,
  }) {
    final current = _activeCompleter;

    switch (policy.kind) {
      case CommandPolicyKind.drop:
        if (current != null) {
          _emitPolicyEvent(
            decision: CommandPolicyDecision.coalesced,
            invocationId: invocationId,
            executionId: _activeExecutionId,
            reason: CommandPolicyReason.activeDrop,
          );
          final future = callerCompleter == null
              ? current.future
              : _bridgeFuture(current.future, callerCompleter);
          return _CommandSubmission<A, E>(future: future, rememberInput: false);
        }
        return _startExecution(
          createEffect,
          invocationId: invocationId,
          completion: callerCompleter,
        );

      case CommandPolicyKind.latest:
        final previousId = _activeExecutionId;
        if (current != null && policy.cancelPrevious && previousId != null) {
          final interrupted = _runtimeExecutions[previousId]?.interrupt(
            reason: 'command-policy-latest-superseded',
          );
          if (interrupted ?? false) {
            _emitPolicyEvent(
              decision: CommandPolicyDecision.interruptedPrevious,
              invocationId: invocationId,
              executionId: previousId,
              reason: CommandPolicyReason.latestSuperseded,
            );
          }
        }
        return _startExecution(
          createEffect,
          invocationId: invocationId,
          completion: callerCompleter,
        );

      case CommandPolicyKind.queue:
        if (current == null) {
          return _startExecution(
            createEffect,
            invocationId: invocationId,
            completion: callerCompleter,
          );
        }
        return _enqueueWithPolicy(
          createEffect,
          invocationId: invocationId,
          completion: callerCompleter,
        );
    }
  }

  _CommandSubmission<A, E> _submitDebounced(
    Effect<A, E> Function() createEffect, {
    required int invocationId,
  }) {
    final trigger = policy.trigger;

    if (!_triggerWindowOpen && trigger.leading) {
      try {
        _restartTriggerTimer(trigger, invocationId: invocationId);
      } catch (error, stackTrace) {
        return _policyDefectSubmission(
          invocationId: invocationId,
          error: error,
          stackTrace: stackTrace,
        );
      }
      _triggerWindowOpen = true;
      return _coordinateInvocation(createEffect, invocationId: invocationId);
    }

    if (!trigger.trailing) {
      try {
        _restartTriggerTimer(trigger, invocationId: invocationId);
      } catch (error, stackTrace) {
        return _policyDefectSubmission(
          invocationId: invocationId,
          error: error,
          stackTrace: stackTrace,
        );
      }
      _triggerWindowOpen = true;
      _emitPolicyEvent(
        decision: CommandPolicyDecision.rejected,
        invocationId: invocationId,
        reason: CommandPolicyReason.debounceSuppressed,
      );
      return _interruptedSubmission(rememberInput: false);
    }

    final pending = _TriggeredEffectExecution<A, E>(invocationId, createEffect);
    _replacePendingTrigger(
      pending,
      reason: CommandPolicyReason.debounceReplaced,
    );

    try {
      _restartTriggerTimer(trigger, invocationId: invocationId);
    } catch (error, stackTrace) {
      if (identical(_pendingTrigger, pending)) {
        _pendingTrigger = null;
      }
      return _policyDefectSubmission(
        invocationId: invocationId,
        error: error,
        stackTrace: stackTrace,
        completion: pending.completer,
      );
    }

    _triggerWindowOpen = true;
    _emitPolicyEvent(
      decision: CommandPolicyDecision.triggerScheduled,
      invocationId: invocationId,
    );
    return _CommandSubmission<A, E>(
      future: pending.completer.future,
      rememberInput: true,
    );
  }

  _CommandSubmission<A, E> _submitThrottled(
    Effect<A, E> Function() createEffect, {
    required int invocationId,
  }) {
    final trigger = policy.trigger;

    if (!_triggerWindowOpen) {
      try {
        _restartTriggerTimer(trigger, invocationId: invocationId);
      } catch (error, stackTrace) {
        return _policyDefectSubmission(
          invocationId: invocationId,
          error: error,
          stackTrace: stackTrace,
        );
      }
      _triggerWindowOpen = true;

      if (trigger.leading) {
        return _coordinateInvocation(createEffect, invocationId: invocationId);
      }

      final pending = _TriggeredEffectExecution<A, E>(
        invocationId,
        createEffect,
      );
      _pendingTrigger = pending;
      _emitPolicyEvent(
        decision: CommandPolicyDecision.triggerScheduled,
        invocationId: invocationId,
      );
      return _CommandSubmission<A, E>(
        future: pending.completer.future,
        rememberInput: true,
      );
    }

    if (!trigger.trailing) {
      _emitPolicyEvent(
        decision: CommandPolicyDecision.rejected,
        invocationId: invocationId,
        reason: CommandPolicyReason.throttleSuppressed,
      );
      return _interruptedSubmission(rememberInput: false);
    }

    final pending = _TriggeredEffectExecution<A, E>(invocationId, createEffect);
    _replacePendingTrigger(
      pending,
      reason: CommandPolicyReason.throttleReplaced,
    );
    _emitPolicyEvent(
      decision: CommandPolicyDecision.triggerScheduled,
      invocationId: invocationId,
    );
    return _CommandSubmission<A, E>(
      future: pending.completer.future,
      rememberInput: true,
    );
  }

  _CommandSubmission<A, E> _enqueueWithPolicy(
    Effect<A, E> Function() createEffect, {
    required int invocationId,
    Completer<Exit<A, E>>? completion,
  }) {
    final maximum = policy.maxPending;
    final hasCapacity = maximum == null || _queue.length < maximum;
    final caller = completion ?? Completer<Exit<A, E>>();

    if (!hasCapacity) {
      if (policy.overflow == QueueOverflow.dropOldest && _queue.isNotEmpty) {
        final dropped = _queue.removeFirst();
        _completeInterrupted(dropped.completer);
        _emitPolicyEvent(
          decision: CommandPolicyDecision.dropped,
          invocationId: dropped.invocationId,
          reason: CommandPolicyReason.queueDroppedOldest,
        );
      } else {
        _completeInterrupted(caller);
        final isRejected = policy.overflow == QueueOverflow.rejectNewest;
        _emitPolicyEvent(
          decision: isRejected
              ? CommandPolicyDecision.rejected
              : CommandPolicyDecision.dropped,
          invocationId: invocationId,
          reason: isRejected
              ? CommandPolicyReason.queueRejectedNewest
              : CommandPolicyReason.queueDroppedNewest,
        );
        return _CommandSubmission<A, E>(
          future: caller.future,
          rememberInput: false,
        );
      }
    }

    _queue.addLast(
      _QueuedEffectExecution<A, E>(invocationId, createEffect, caller),
    );
    _emitPolicyEvent(
      decision: CommandPolicyDecision.queued,
      invocationId: invocationId,
    );
    return _CommandSubmission<A, E>(future: caller.future, rememberInput: true);
  }

  _CommandSubmission<A, E> _startExecution(
    Effect<A, E> Function() createEffect, {
    required int invocationId,
    Completer<Exit<A, E>>? completion,
  }) {
    final executionId = ++_nextExecutionId;
    final caller = completion ?? Completer<Exit<A, E>>();

    _activeExecutionId = executionId;
    _activeCompleter = caller;
    _pendingCompletions[executionId] = caller;

    _setState(
      EffectCommandRunning<A, E>._(
        revision: _nextRevision(),
        executionId: executionId,
        startedAt: DateTime.now(),
        previous: _retainedData,
      ),
    );
    _emitPolicyEvent(
      decision: CommandPolicyDecision.started,
      invocationId: invocationId,
      executionId: executionId,
    );

    final tracked = _trackExecution(createEffect, executionId, caller);
    _inFlight = tracked;

    return _CommandSubmission<A, E>(future: caller.future, rememberInput: true);
  }

  Future<Exit<A, E>> _runEffect(
    Effect<A, E> Function() createEffect,
    int executionId,
  ) async {
    Exit<A, E> exit;

    try {
      final runtimeExecution = _runtime.execute(
        createEffect(),
        label: debugLabel,
      );
      _runtimeExecutions[executionId] = runtimeExecution;
      if (_owns(executionId)) {
        _activeRuntimeExecution = runtimeExecution;
      }
      exit = await runtimeExecution.exit;
    } catch (error, stackTrace) {
      exit = ExitDefect<A, E>(error, stackTrace);
    }

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

  Future<Exit<A, E>> _trackExecution(
    Effect<A, E> Function() createEffect,
    int executionId,
    Completer<Exit<A, E>> completion,
  ) async {
    try {
      final exit = await _runEffect(createEffect, executionId);
      if (!completion.isCompleted) completion.complete(exit);
      return exit;
    } catch (error, stackTrace) {
      if (!completion.isCompleted) {
        completion.completeError(error, stackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _runtimeExecutions.remove(executionId);
      _pendingCompletions.remove(executionId);

      if (!_disposed && _activeExecutionId == executionId) {
        _inFlight = null;
        _activeCompleter = null;
        _activeRuntimeExecution = null;
        _activeExecutionId = null;
        _startNextQueuedIfPossible();
      }
    }
  }

  void _startNextQueuedIfPossible() {
    if (_disposed ||
        policy.kind != CommandPolicyKind.queue ||
        _activeCompleter != null ||
        _queue.isEmpty) {
      return;
    }

    final next = _queue.removeFirst();
    _startExecution(
      next.createEffect,
      invocationId: next.invocationId,
      completion: next.completer,
    );
  }

  void _restartTriggerTimer(
    TriggerPolicy trigger, {
    required int invocationId,
  }) {
    final clock = _triggerClock ??= _runtime.services<EffectClock>();
    _supersedeTriggerTimer();

    final generation = ++_triggerGeneration;
    final execution = _runtime.execute(
      Effect<_CommandTriggerToken, Never>.result((use) async {
        await clock.sleep(trigger.duration, use.cancellation);
        return const _CommandTriggerToken();
      }),
      label: '${debugLabel ?? runtimeType}.trigger.${trigger.kind.name}',
    );
    _triggerExecution = execution;
    unawaited(
      _watchTriggerTimer(
        execution,
        generation: generation,
        kind: trigger.kind,
        invocationId: invocationId,
      ),
    );
  }

  Future<void> _watchTriggerTimer(
    EffectExecution<_CommandTriggerToken, Never> execution, {
    required int generation,
    required TriggerPolicyKind kind,
    required int invocationId,
  }) async {
    final exit = await execution.exit;
    if (_disposed || generation != _triggerGeneration) return;

    _triggerExecution = null;

    switch (exit) {
      case ExitSuccess<_CommandTriggerToken, Never>():
        _emitPolicyEvent(
          decision: CommandPolicyDecision.triggerFired,
          invocationId: _pendingTrigger?.invocationId ?? invocationId,
        );
        _onTriggerFired(kind);

      case ExitInterrupted<_CommandTriggerToken, Never>():
        _triggerWindowOpen = false;
        _interruptPendingTrigger(CommandPolicyReason.commandCancelled);

      case ExitDefect<_CommandTriggerToken, Never>(
        :final defect,
        :final stackTrace,
      ):
        _triggerWindowOpen = false;
        final pending = _pendingTrigger;
        if (pending != null) {
          _pendingTrigger = null;
          _policyDefectSubmission(
            invocationId: pending.invocationId,
            error: defect,
            stackTrace: stackTrace,
            completion: pending.completer,
          );
        } else {
          _emitPolicyEvent(
            decision: CommandPolicyDecision.defect,
            invocationId: invocationId,
            reason: CommandPolicyReason.triggerClockFailed,
          );
          _reportObserverError(defect, stackTrace);
        }

      case ExitFailure<_CommandTriggerToken, Never>():
        final error = StateError(
          'A Command trigger timer produced an impossible typed failure.',
        );
        _triggerWindowOpen = false;
        _reportObserverError(error, StackTrace.current);
    }
  }

  void _onTriggerFired(TriggerPolicyKind kind) {
    final pending = _pendingTrigger;
    _pendingTrigger = null;

    if (kind == TriggerPolicyKind.debounce) {
      _triggerWindowOpen = false;
      if (pending != null) {
        _coordinateInvocation(
          pending.createEffect,
          invocationId: pending.invocationId,
          callerCompleter: pending.completer,
        );
      }
      return;
    }

    if (pending == null) {
      _triggerWindowOpen = false;
      return;
    }

    _coordinateInvocation(
      pending.createEffect,
      invocationId: pending.invocationId,
      callerCompleter: pending.completer,
    );

    try {
      _restartTriggerTimer(policy.trigger, invocationId: pending.invocationId);
      _triggerWindowOpen = true;
    } catch (error, stackTrace) {
      _triggerWindowOpen = false;
      _emitPolicyEvent(
        decision: CommandPolicyDecision.defect,
        invocationId: pending.invocationId,
        reason: CommandPolicyReason.triggerClockFailed,
      );
      _reportObserverError(error, stackTrace);
    }
  }

  void _supersedeTriggerTimer() {
    final previous = _triggerExecution;
    if (previous == null) return;

    _triggerExecution = null;
    _triggerGeneration++;
    previous.interrupt(reason: 'command-trigger-replaced');
  }

  bool _cancelTriggerWindow(CommandPolicyReason reason) {
    final hadWindow = _triggerWindowOpen || _triggerExecution != null;
    final execution = _triggerExecution;
    _triggerExecution = null;
    _triggerWindowOpen = false;
    _triggerGeneration++;
    execution?.interrupt(reason: reason.name);
    return hadWindow;
  }

  void _replacePendingTrigger(
    _TriggeredEffectExecution<A, E> pending, {
    required CommandPolicyReason reason,
  }) {
    final previous = _pendingTrigger;
    if (previous != null) {
      _completeInterrupted(previous.completer);
      _emitPolicyEvent(
        decision: CommandPolicyDecision.replaced,
        invocationId: previous.invocationId,
        reason: reason,
      );
    }
    _pendingTrigger = pending;
  }

  bool _interruptPendingTrigger(CommandPolicyReason reason) {
    final pending = _pendingTrigger;
    if (pending == null) return false;

    _pendingTrigger = null;
    _completeInterrupted(pending.completer);
    _emitPolicyEvent(
      decision: CommandPolicyDecision.cancelled,
      invocationId: pending.invocationId,
      reason: reason,
    );
    return true;
  }

  bool _interruptQueued(CommandPolicyReason reason) {
    var changed = false;
    while (_queue.isNotEmpty) {
      changed = true;
      final queued = _queue.removeFirst();
      _completeInterrupted(queued.completer);
      _emitPolicyEvent(
        decision: CommandPolicyDecision.cancelled,
        invocationId: queued.invocationId,
        reason: reason,
      );
    }
    return changed;
  }

  _CommandSubmission<A, E> _policyDefectSubmission({
    required int invocationId,
    required Object error,
    required StackTrace stackTrace,
    Completer<Exit<A, E>>? completion,
  }) {
    final caller = completion ?? Completer<Exit<A, E>>();
    final defect = ExitDefect<A, E>(error, stackTrace);
    _lastExit = defect;
    final executionId = ++_nextExecutionId;

    if (!caller.isCompleted) caller.complete(defect);
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
    _emitPolicyEvent(
      decision: CommandPolicyDecision.defect,
      invocationId: invocationId,
      executionId: executionId,
      reason: CommandPolicyReason.triggerClockUnavailable,
    );

    return _CommandSubmission<A, E>(
      future: caller.future,
      rememberInput: false,
    );
  }

  _CommandSubmission<A, E> _interruptedSubmission({
    required bool rememberInput,
  }) {
    return _CommandSubmission<A, E>(
      future: Future<Exit<A, E>>.value(ExitInterrupted<A, E>()),
      rememberInput: rememberInput,
    );
  }

  Future<Exit<A, E>> _bridgeFuture(
    Future<Exit<A, E>> source,
    Completer<Exit<A, E>> target,
  ) {
    source.then<void>(
      (exit) {
        if (!target.isCompleted) target.complete(exit);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!target.isCompleted) target.completeError(error, stackTrace);
      },
    );
    return target.future;
  }

  void _completeInterrupted(Completer<Exit<A, E>> completer) {
    if (!completer.isCompleted) {
      completer.complete(ExitInterrupted<A, E>());
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError(
        '${debugLabel ?? runtimeType} was used after it was disposed.',
      );
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

  void _emitPolicyEvent({
    required CommandPolicyDecision decision,
    required int invocationId,
    int? executionId,
    CommandPolicyReason? reason,
  }) {
    final event = EffectCommandPolicyEvent(
      policy: policy,
      decision: decision,
      timestamp: DateTime.now(),
      invocationId: invocationId,
      executionId: executionId,
      pendingCount: pendingCount,
      queuedCount: queuedCount,
      reason: reason,
      debugLabel: debugLabel,
    );

    final shared = _sharedPolicyObserver;
    if (shared != null) {
      try {
        shared(event);
      } catch (error, stackTrace) {
        _reportObserverError(error, stackTrace);
      }
    }

    final local = _policyObserver;
    if (local != null && !identical(local, shared)) {
      try {
        local(event);
      } catch (error, stackTrace) {
        _reportObserverError(error, stackTrace);
      }
    }
  }

  void _setState(EffectCommandState<A, E> state) {
    if (_disposed) return;

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
}

/// The minimal lifecycle contract shared by all Effect command variants.
abstract interface class EffectCommandDisposable {
  bool get isDisposed;

  void dispose();
}

final class _CommandSubmission<A extends Object, E extends Object> {
  const _CommandSubmission({required this.future, required this.rememberInput});

  final Future<Exit<A, E>> future;
  final bool rememberInput;
}

final class _QueuedEffectExecution<A extends Object, E extends Object> {
  const _QueuedEffectExecution(
    this.invocationId,
    this.createEffect,
    this.completer,
  );

  final int invocationId;
  final Effect<A, E> Function() createEffect;
  final Completer<Exit<A, E>> completer;
}

final class _TriggeredEffectExecution<A extends Object, E extends Object> {
  _TriggeredEffectExecution(this.invocationId, this.createEffect)
    : completer = Completer<Exit<A, E>>();

  final int invocationId;
  final Effect<A, E> Function() createEffect;
  final Completer<Exit<A, E>> completer;
}

final class _CommandTriggerToken {
  const _CommandTriggerToken();
}
