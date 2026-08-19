part of '../../better_effect.dart';

typedef _ScopeFinalizer = FutureOr<void> Function(Exit<Object, Object> exit);

/// Owns finalizers for resources acquired during a runtime or Effect execution.
final class Scope {
  Scope._([this._parent]);

  final Scope? _parent;
  final List<_ScopeFinalizer> _finalizers = <_ScopeFinalizer>[];
  final Set<Scope> _children = <Scope>{};
  bool _closed = false;
  Future<void>? _closingFuture;

  bool get isClosed => _closed;

  Scope _fork() {
    if (_closed) {
      throw const ScopeClosedException();
    }

    final child = Scope._(this);
    _children.add(child);
    return child;
  }

  void _addFinalizer(_ScopeFinalizer finalizer) {
    if (_closed) {
      throw const ScopeClosedException();
    }

    _finalizers.add(finalizer);
  }

  Future<void> _close(Exit<Object, Object> exit) {
    if (_closed) {
      return _closingFuture ?? Future<void>.value();
    }

    _closed = true;
    final closing = _closeScope(exit);
    _closingFuture = closing;
    return closing;
  }

  Future<void> _closeScope(Exit<Object, Object> exit) async {
    final failures = <ReleaseFailure>[];

    for (final child in List<Scope>.of(_children)) {
      try {
        await child._close(exit);
      } catch (error, stackTrace) {
        failures.add((error: error, stackTrace: stackTrace));
      }
    }

    try {
      for (final finalizer in _finalizers.reversed) {
        try {
          await Future<void>.sync(() => finalizer(exit));
        } catch (error, stackTrace) {
          failures.add((error: error, stackTrace: stackTrace));
        }
      }
    } finally {
      _finalizers.clear();
      _children.clear();
      _parent?._children.remove(this);
    }

    if (failures.isNotEmpty) {
      throw ScopeReleaseException(failures);
    }
  }
}
