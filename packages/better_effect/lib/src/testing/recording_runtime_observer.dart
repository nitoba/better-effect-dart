import 'dart:async';

import 'package:better_effect/better_effect.dart';

/// Records Runtime events in callback order for assertions and diagnostics.
///
/// The observer is synchronous, just like [RuntimeObserver]. Waiting APIs are
/// completed from the same callback without introducing work into the Runtime.
final class RecordingRuntimeObserver extends RuntimeObserver {
  final List<Object> _events = <Object>[];
  final List<_RuntimeEventWaiter> _waiters = <_RuntimeEventWaiter>[];
  final Set<int> _activeExecutionIds = <int>{};
  bool _disposed = false;

  /// Immutable snapshot of every recorded event.
  List<Object> get events => List<Object>.unmodifiable(_events);

  /// Managed executions that started but have not emitted physical completion.
  Set<int> get activeExecutionIds => Set<int>.unmodifiable(_activeExecutionIds);

  /// Whether this recorder no longer accepts events or waiters.
  bool get isDisposed => _disposed;

  /// Number of currently waiting event queries.
  int get pendingWaiterCount => _waiters.length;

  /// Recorded events assignable to [T], in callback order.
  Iterable<T> eventsOf<T extends Object>() {
    return _events.whereType<T>();
  }

  /// Latest event assignable to [T], or null when none was recorded.
  T? lastOf<T extends Object>() {
    for (var index = _events.length - 1; index >= 0; index--) {
      final event = _events[index];
      if (event is T) return event;
    }
    return null;
  }

  /// Return the first previously recorded event assignable to [T].
  T? firstWhere<T extends Object>([bool Function(T event)? where]) {
    for (final event in _events) {
      if (event is T && (where?.call(event) ?? true)) {
        return event;
      }
    }
    return null;
  }

  /// Clear recorded history without affecting active waiters or execution
  /// ownership tracking.
  void clear() {
    _ensureOpen();
    _events.clear();
  }

  /// Wait for the next event assignable to [T] that satisfies [where].
  ///
  /// A zero timeout disables the timeout and waits until an event or [dispose].
  Future<T> next<T extends Object>({
    bool Function(T event)? where,
    Duration timeout = const Duration(seconds: 5),
  }) {
    _ensureOpen();
    if (timeout.isNegative) {
      throw ArgumentError.value(timeout, 'timeout', 'must not be negative');
    }

    final completer = Completer<Object>.sync();
    late final _RuntimeEventWaiter waiter;
    waiter = _RuntimeEventWaiter(
      matches: (event) => event is T && (where?.call(event) ?? true),
      completer: completer,
    );
    _waiters.add(waiter);

    Future<Object> future = completer.future;
    if (timeout != Duration.zero) {
      future = future.timeout(
        timeout,
        onTimeout: () {
          _waiters.remove(waiter);
          throw RuntimeEventWaitTimeoutException(T, timeout);
        },
      );
    }

    return future.then<T>((event) => event as T);
  }

  /// Stop recording and fail all pending waiters.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    final error = const RecordingRuntimeObserverDisposedException();
    for (final waiter in List<_RuntimeEventWaiter>.of(_waiters)) {
      if (!waiter.completer.isCompleted) {
        waiter.completer.completeError(error, StackTrace.current);
      }
    }
    _waiters.clear();
  }

  @override
  void onExecutionStart(ExecutionStartEvent event) {
    _activeExecutionIds.add(event.context.executionId);
    _record(event);
  }

  @override
  void onExecutionEnd(ExecutionEndEvent event) {
    _activeExecutionIds.remove(event.context.executionId);
    _record(event);
  }

  @override
  void onServiceResolve(ServiceResolveEvent event) => _record(event);

  @override
  void onServiceAcquire(ServiceAcquireEvent event) => _record(event);

  @override
  void onResourceRelease(ResourceReleaseEvent event) => _record(event);

  @override
  void onInterruption(InterruptionEvent event) => _record(event);

  @override
  void onRetry(RetryEvent event) => _record(event);

  @override
  void onCleanupFailure(CleanupFailureEvent event) => _record(event);

  void _record(Object event) {
    if (_disposed) return;
    _events.add(event);

    for (final waiter in List<_RuntimeEventWaiter>.of(_waiters)) {
      if (!waiter.matches(event)) continue;
      _waiters.remove(waiter);
      if (!waiter.completer.isCompleted) {
        waiter.completer.complete(event);
      }
    }
  }

  void _ensureOpen() {
    if (_disposed) {
      throw const RecordingRuntimeObserverDisposedException();
    }
  }
}

final class _RuntimeEventWaiter {
  const _RuntimeEventWaiter({required this.matches, required this.completer});

  final bool Function(Object event) matches;
  final Completer<Object> completer;
}

/// Raised when [RecordingRuntimeObserver.next] did not observe a matching event.
final class RuntimeEventWaitTimeoutException implements Exception {
  const RuntimeEventWaitTimeoutException(this.eventType, this.timeout);

  final Type eventType;
  final Duration timeout;

  @override
  String toString() {
    return 'No $eventType Runtime event was observed within $timeout.';
  }
}

/// Raised when a disposed recorder is used again.
final class RecordingRuntimeObserverDisposedException implements Exception {
  const RecordingRuntimeObserverDisposedException();

  @override
  String toString() => 'The RecordingRuntimeObserver is disposed.';
}
