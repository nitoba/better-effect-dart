import 'dart:async';

/// A deterministic one-value gate for coordinating asynchronous tests.
///
/// Prefer this to arbitrary sleeps when a test needs to control exactly when an
/// Effect or resource acquisition continues.
final class TestGate<T extends Object> {
  final Completer<T> _completer = Completer<T>.sync();

  /// Whether this gate was completed successfully or with an error.
  bool get isCompleted => _completer.isCompleted;

  /// Future awaited by the code under test.
  Future<T> get future => _completer.future;

  /// Open the gate with [value].
  void complete(T value) {
    if (_completer.isCompleted) {
      throw const TestGateAlreadyCompletedException();
    }
    _completer.complete(value);
  }

  /// Open the gate with an asynchronous failure.
  void completeError(Object error, [StackTrace? stackTrace]) {
    if (_completer.isCompleted) {
      throw const TestGateAlreadyCompletedException();
    }
    _completer.completeError(error, stackTrace ?? StackTrace.current);
  }
}

/// A deterministic signal for tests that only need to release a wait point.
final class TestSignal {
  final Completer<void> _completer = Completer<void>.sync();

  bool get isSignalled => _completer.isCompleted;

  Future<void> get wait => _completer.future;

  void signal() {
    if (_completer.isCompleted) {
      throw const TestGateAlreadyCompletedException();
    }
    _completer.complete();
  }
}

/// Records an ordered sequence such as resource acquisition and cleanup events.
final class TestEventRecorder<T extends Object> {
  final List<T> _events = <T>[];

  List<T> get events => List<T>.unmodifiable(_events);

  void record(T event) => _events.add(event);

  void clear() => _events.clear();

  /// Verify an exact ordered sequence without depending on a test framework.
  void expectEvents(Iterable<T> expected) {
    final expectedValues = List<T>.of(expected);
    if (_events.length == expectedValues.length) {
      var matches = true;
      for (var index = 0; index < _events.length; index++) {
        if (_events[index] != expectedValues[index]) {
          matches = false;
          break;
        }
      }
      if (matches) return;
    }

    throw TestEventSequenceException(expected: expectedValues, actual: events);
  }
}

final class TestGateAlreadyCompletedException implements Exception {
  const TestGateAlreadyCompletedException();

  @override
  String toString() => 'The test gate was already completed.';
}

final class TestEventSequenceException<T extends Object> implements Exception {
  const TestEventSequenceException({
    required this.expected,
    required this.actual,
  });

  final List<T> expected;
  final List<T> actual;

  @override
  String toString() => 'Expected events $expected, but recorded $actual.';
}
