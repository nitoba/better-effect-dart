part of '../../better_effect.dart';

/// A cleanup callback registered with a [Scope].
typedef ScopeFinalizer = FutureOr<void> Function(Exit<Object, Object> exit);

/// Releases a resource with the outcome that closed its owning [Scope].
typedef ResourceRelease<R extends Object> =
    FutureOr<void> Function(R resource, Exit<Object, Object> exit);

/// Owns finalizers, resources, and child Scopes.
///
/// Scopes close children before their own finalizers and use reverse creation
/// order throughout. Code that creates a Scope with [Scope.make] owns it and
/// must call [close]. Runtime-managed execution Scopes are not exposed directly.
final class Scope {
  Scope._([this._parent]);

  /// Create an owned, initially open Scope.
  static Scope make() => Scope._();

  final Scope? _parent;
  final List<ScopeFinalizer> _finalizers = <ScopeFinalizer>[];
  final Set<Scope> _children = LinkedHashSet<Scope>.identity();
  final Set<Future<void>> _physicalOperations = <Future<void>>{};
  final List<ReleaseFailure> _physicalFailures = <ReleaseFailure>[];
  bool _closed = false;
  Future<void>? _closingFuture;
  Exit<Object, Object>? _closingExit;

  /// Whether closing has started for this Scope.
  bool get isClosed => _closed;

  /// Create a child owned by this Scope.
  Scope fork() {
    _ensureOpen();

    final child = Scope._(this);
    _children.add(child);
    return child;
  }

  /// Register a finalizer that runs when this Scope closes.
  void addFinalizer(ScopeFinalizer finalizer) {
    _ensureOpen();
    _finalizers.add(finalizer);
  }

  /// Acquire a resource and atomically register its outcome-aware release.
  ///
  /// If the Scope closes while [operation] is pending, the acquired resource is
  /// released immediately with the closing outcome instead of being leaked.
  Future<R> acquire<R extends Object>(
    FutureOr<R> Function() operation,
    ResourceRelease<R> release,
  ) async {
    _ensureOpen();
    final resource = await Future<R>.sync(operation);

    try {
      addFinalizer((exit) => release(resource, exit));
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

  /// Close this Scope and every child Scope.
  ///
  /// Concurrent and repeated callers receive the same completion. Children are
  /// closed child-first in reverse creation order, followed by this Scope's
  /// finalizers in reverse registration order. All release failures are
  /// aggregated after every cleanup has been attempted.
  Future<void> close(Exit<Object, Object> exit) {
    if (_closed) {
      return _closingFuture ?? Future<void>.value();
    }

    _closed = true;
    _closingExit = exit;
    final closing = _closeScope(exit);
    _closingFuture = closing;
    return closing;
  }

  Scope _fork() => fork();

  Future<R> _acquire<R extends Object>(
    FutureOr<R> Function() operation,
    ResourceRelease<R> release,
  ) {
    return acquire(operation, release);
  }

  Future<void> _close(Exit<Object, Object> exit) => close(exit);

  void _trackPhysical(Future<void> operation) {
    _ensureOpen();

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

  Future<void> _closeScope(Exit<Object, Object> exit) async {
    final failures = <ReleaseFailure>[];
    final children = List<Scope>.of(_children);

    for (final child in children.reversed) {
      try {
        await child.close(exit);
      } catch (error, stackTrace) {
        if (error is ScopeReleaseException) {
          failures.addAll(error.failures);
        } else {
          failures.add((error: error, stackTrace: stackTrace));
        }
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

  void _ensureOpen() {
    if (_closed) {
      throw const ScopeClosedException();
    }
  }
}
