part of '../../better_effect.dart';

typedef _ScopeFinalizer = FutureOr<void> Function(Exit<Object, Object> exit);

/// Owns finalizers for resources acquired during a runtime or Effect execution.
final class Scope {
  Scope._();

  final List<_ScopeFinalizer> _finalizers = <_ScopeFinalizer>[];
  bool _closed = false;

  bool get isClosed => _closed;

  void _addFinalizer(_ScopeFinalizer finalizer) {
    if (_closed) {
      throw const ScopeClosedException();
    }

    _finalizers.add(finalizer);
  }

  Future<void> _close(Exit<Object, Object> exit) async {
    if (_closed) {
      return;
    }

    _closed = true;
    final failures = <ReleaseFailure>[];

    for (final finalizer in _finalizers.reversed) {
      try {
        await Future<void>.sync(() => finalizer(exit));
      } catch (error, stackTrace) {
        failures.add((error: error, stackTrace: stackTrace));
      }
    }

    _finalizers.clear();

    if (failures.isNotEmpty) {
      throw ScopeReleaseException(failures);
    }
  }
}
