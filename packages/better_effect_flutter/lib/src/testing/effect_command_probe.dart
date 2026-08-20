import 'dart:async';

import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:flutter/foundation.dart';

/// Records visible [EffectCommandState] revisions without owning the Command.
///
/// Dispose the probe before disposing the observed Command, or use a test
/// teardown that disposes both.
final class EffectCommandProbe<A extends Object, E extends Object> {
  EffectCommandProbe(this.command, {bool includeInitial = true}) {
    if (includeInitial) {
      _record(command.value);
    }
    command.addListener(_handleChange);
  }

  final ValueListenable<EffectCommandState<A, E>> command;
  final List<EffectCommandState<A, E>> _states = <EffectCommandState<A, E>>[];
  final List<_CommandStateWaiter<A, E>> _waiters =
      <_CommandStateWaiter<A, E>>[];
  bool _disposed = false;

  /// Immutable snapshot of recorded visible states.
  List<EffectCommandState<A, E>> get states {
    return List<EffectCommandState<A, E>>.unmodifiable(_states);
  }

  /// Latest recorded state, or null when initial recording was disabled and no
  /// transition has happened yet.
  EffectCommandState<A, E>? get lastState {
    return _states.isEmpty ? null : _states.last;
  }

  bool get isDisposed => _disposed;

  int get pendingWaiterCount => _waiters.length;

  /// Recorded states assignable to [S].
  Iterable<S> statesOf<S extends EffectCommandState<A, E>>() {
    return _states.whereType<S>();
  }

  /// Remove recorded history without changing active waiters.
  void clear() {
    _ensureOpen();
    _states.clear();
  }

  /// Wait until the current or a future state satisfies [where].
  Future<EffectCommandState<A, E>> waitUntil(
    bool Function(EffectCommandState<A, E> state) where, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    _ensureOpen();

    final current = command.value;
    if (where(current)) {
      return Future<EffectCommandState<A, E>>.value(current);
    }

    return _wait(where, timeout: timeout);
  }

  /// Wait for a future state satisfying [where]. Previously recorded states are
  /// ignored.
  Future<EffectCommandState<A, E>> nextWhere(
    bool Function(EffectCommandState<A, E> state) where, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    _ensureOpen();
    return _wait(where, timeout: timeout);
  }

  /// Wait for the current or next state assignable to [S].
  Future<S> waitFor<S extends EffectCommandState<A, E>>({
    bool Function(S state)? where,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final state = await waitUntil(
      (state) => state is S && (where?.call(state) ?? true),
      timeout: timeout,
    );
    return state as S;
  }

  /// Verify the exact sequence of recorded runtime types.
  ///
  /// This helper is framework-independent and throws a descriptive exception on
  /// mismatch. Use ordinary matcher assertions when richer value checks are
  /// required.
  void expectStateTypes(Iterable<Type> expected) {
    final expectedValues = List<Type>.of(expected);
    final actualValues = <Type>[for (final state in _states) state.runtimeType];

    if (_sameTypes(actualValues, expectedValues)) return;
    throw EffectCommandProbeExpectationException(
      expected: expectedValues,
      actual: actualValues,
    );
  }

  /// Detach from the Command and fail pending state waiters.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    command.removeListener(_handleChange);

    const error = EffectCommandProbeDisposedException();
    for (final waiter in List<_CommandStateWaiter<A, E>>.of(_waiters)) {
      if (!waiter.completer.isCompleted) {
        waiter.completer.completeError(error, StackTrace.current);
      }
    }
    _waiters.clear();
  }

  Future<EffectCommandState<A, E>> _wait(
    bool Function(EffectCommandState<A, E> state) where, {
    required Duration timeout,
  }) {
    if (timeout.isNegative) {
      throw ArgumentError.value(timeout, 'timeout', 'must not be negative');
    }

    final completer = Completer<EffectCommandState<A, E>>.sync();
    late final _CommandStateWaiter<A, E> waiter;
    waiter = _CommandStateWaiter<A, E>(where: where, completer: completer);
    _waiters.add(waiter);

    Future<EffectCommandState<A, E>> future = completer.future;
    if (timeout != Duration.zero) {
      future = future.timeout(
        timeout,
        onTimeout: () {
          _waiters.remove(waiter);
          throw EffectCommandProbeTimeoutException(timeout);
        },
      );
    }
    return future;
  }

  void _handleChange() {
    _record(command.value);
  }

  void _record(EffectCommandState<A, E> state) {
    if (_disposed) return;
    if (_states.isNotEmpty && _states.last.revision == state.revision) {
      return;
    }

    _states.add(state);
    for (final waiter in List<_CommandStateWaiter<A, E>>.of(_waiters)) {
      if (!waiter.where(state)) continue;
      _waiters.remove(waiter);
      if (!waiter.completer.isCompleted) {
        waiter.completer.complete(state);
      }
    }
  }

  void _ensureOpen() {
    if (_disposed) throw const EffectCommandProbeDisposedException();
  }
}

final class _CommandStateWaiter<A extends Object, E extends Object> {
  const _CommandStateWaiter({required this.where, required this.completer});

  final bool Function(EffectCommandState<A, E> state) where;
  final Completer<EffectCommandState<A, E>> completer;
}

bool _sameTypes(List<Type> actual, List<Type> expected) {
  if (actual.length != expected.length) return false;
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) return false;
  }
  return true;
}

/// Raised when a probe state sequence differs from the expectation.
final class EffectCommandProbeExpectationException implements Exception {
  const EffectCommandProbeExpectationException({
    required this.expected,
    required this.actual,
  });

  final List<Type> expected;
  final List<Type> actual;

  @override
  String toString() {
    return 'Expected Command state types $expected, but recorded $actual.';
  }
}

/// Raised when no matching Command state appears within a timeout.
final class EffectCommandProbeTimeoutException implements Exception {
  const EffectCommandProbeTimeoutException(this.timeout);

  final Duration timeout;

  @override
  String toString() => 'No matching Command state appeared within $timeout.';
}

/// Raised when a disposed probe is reused.
final class EffectCommandProbeDisposedException implements Exception {
  const EffectCommandProbeDisposedException();

  @override
  String toString() => 'The EffectCommandProbe is disposed.';
}
