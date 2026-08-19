part of '../../better_effect.dart';

typedef _ScopeFinalizer = FutureOr<void> Function(Exit<Object, Object> exit);

/// Owns finalizers for resources acquired during a runtime or Effect execution.
final class Scope {
  Scope._([this._parent]);

  final Scope? _parent;
  final List<_ScopeFinalizer> _finalizers = <_ScopeFinalizer>[];
  final Set<Scope> _children = <Scope>{};
  final Set<Future<void>> _physicalOperations = <Future<void>>{};
  final List<ReleaseFailure> _physicalFailures = <ReleaseFailure>[];
  bool _closed = false;
  Future<void>? _closingFuture;
  Exit<Object, Object>? _closingExit;

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

  Future<R> _acquire<R>(
    FutureOr<R> Function() acquire,
    FutureOr<void> Function(R resource, Exit<Object, Object> exit) release,
  ) async {
    // Registering after await is a race with Scope._close; release directly if
    // the scope closed before the finalizer could be installed.
    final resource = await Future<R>.sync(acquire);

    try {
      _addFinalizer((exit) => release(resource, exit));
    } catch (error, stackTrace) {
      try {
        await Future<void>.sync(
          () => release(
            resource,
            _closingExit ?? const ExitInterrupted<Object, Object>(),
          ),
        );
      } catch (releaseError, releaseStackTrace) {
        Error.throwWithStackTrace(
          CompositeDefect(
            primary: error,
            primaryStackTrace: stackTrace,
            secondary: releaseError,
            secondaryStackTrace: releaseStackTrace,
          ),
          stackTrace,
        );
      }

      Error.throwWithStackTrace(error, stackTrace);
    }

    return resource;
  }

  void _trackPhysical(Future<void> operation) {
    if (_closed) {
      throw const ScopeClosedException();
    }

    final completion = Completer<void>.sync();
    final tracked = completion.future;
    _physicalOperations.add(tracked);

    operation.then<void>(
      (_) {
        completion.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        // A late acquire can observe shutdown after releasing successfully.
        if (error is! ScopeClosedException) {
          _physicalFailures.add((error: error, stackTrace: stackTrace));
        }
        completion.complete();
      },
    );
    tracked.then<void>((_) => _physicalOperations.remove(tracked));
  }

  bool get _hasPendingPhysical => _physicalOperations.isNotEmpty;

  Future<void> _awaitPhysical() async {
    while (_physicalOperations.isNotEmpty) {
      await Future.wait<void>(
        List<Future<void>>.of(_physicalOperations),
        eagerError: false,
      );
    }
  }

  Future<void> _close(Exit<Object, Object> exit) {
    if (_closed) {
      return _closingFuture ?? Future<void>.value();
    }

    _closed = true;
    _closingExit = exit;
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
      await _awaitPhysical();
      failures.addAll(_physicalFailures);
      _physicalFailures.clear();

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
