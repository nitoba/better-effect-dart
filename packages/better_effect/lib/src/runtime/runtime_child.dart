part of '../../better_effect.dart';

int _nextRuntimeId = 0;

int _allocateRuntimeId() => ++_nextRuntimeId;

final Expando<_RuntimeScopeMetadata> _runtimeScopeMetadata =
    Expando<_RuntimeScopeMetadata>('better_effect.runtime.scope');
final Expando<Set<Runtime>> _runtimeChildren = Expando<Set<Runtime>>(
  'better_effect.runtime.children',
);

final class _RuntimeScopeMetadata {
  const _RuntimeScopeMetadata({
    required this.runtimeId,
    required this.parentRuntimeId,
    required this.runtimeLabel,
  });

  final int runtimeId;
  final int? parentRuntimeId;
  final String? runtimeLabel;
}

_RuntimeScopeMetadata _runtimeMetadataForScope(Scope scope) {
  var root = scope;
  while (root._parent != null) {
    root = root._parent;
  }

  final existing = _runtimeScopeMetadata[root];
  if (existing != null) {
    return existing;
  }

  final metadata = _RuntimeScopeMetadata(
    runtimeId: _allocateRuntimeId(),
    parentRuntimeId: null,
    runtimeLabel: null,
  );
  _runtimeScopeMetadata[root] = metadata;
  return metadata;
}

Set<Runtime> _childrenOf(Runtime runtime) {
  return _runtimeChildren[runtime] ??= LinkedHashSet<Runtime>.identity();
}

Future<void> _closeRuntimeChildren(
  Runtime runtime,
  Exit<Object, Object> exit, {
  required Duration gracePeriod,
  required bool interruptAfterGracePeriod,
}) async {
  final registry = _childrenOf(runtime);
  final children = List<Runtime>.of(registry).reversed;
  Object? closeError;
  StackTrace? closeStackTrace;

  void capture(Object error, StackTrace stackTrace) {
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

  for (final child in children) {
    try {
      await child._closeWith(
        exit,
        gracePeriod: gracePeriod,
        interruptAfterGracePeriod: interruptAfterGracePeriod,
      );
    } catch (error, stackTrace) {
      capture(error, stackTrace);
    }
  }

  registry.removeWhere((child) => child.isClosed);

  final error = closeError;
  if (error != null) {
    Error.throwWithStackTrace(error, closeStackTrace!);
  }
}

/// Child Runtime operations for feature-length environments.
extension RuntimeChildOps on Runtime {
  /// Stable identity of this Runtime within the current isolate.
  int get runtimeId => _runtimeMetadataForScope(_rootContext.scope).runtimeId;

  /// Stable identity of the parent Runtime, or null for an application root.
  int? get parentRuntimeId =>
      _runtimeMetadataForScope(_rootContext.scope).parentRuntimeId;

  /// Optional diagnostic label assigned when this Runtime was forked.
  String? get runtimeLabel =>
      _runtimeMetadataForScope(_rootContext.scope).runtimeLabel;

  /// Whether this Runtime resolves through a parent environment.
  bool get isChildRuntime => parentRuntimeId != null;

  /// Create a Runtime whose local Module shadows and falls back to this Runtime.
  ///
  /// Unlike `runWith`, the returned Runtime owns its providers and resources
  /// until [Runtime.close]. Parent shutdown closes active children with the same
  /// grace/interruption policy before releasing parent resources.
  Future<Runtime> fork(Module module, {String? label}) async {
    _ensureActive();

    final overlay = _createExecutionOverlay(_rootContext.backend);
    final rootScope = Scope._();
    final metadata = _RuntimeScopeMetadata(
      runtimeId: _allocateRuntimeId(),
      parentRuntimeId: runtimeId,
      runtimeLabel: label,
    );
    _runtimeScopeMetadata[rootScope] = metadata;

    final observation = _observers == null
        ? null
        : _ExecutionObservation(
            observers: _observers,
            executionId: 0,
            executionLabel: null,
            parentExecutionId: null,
            runtimeId: metadata.runtimeId,
            parentRuntimeId: metadata.parentRuntimeId,
            runtimeLabel: metadata.runtimeLabel,
            startedAt: DateTime.now(),
            initialMetadata: const <String, Object>{},
          );
    final context = _RuntimeContext(
      backend: overlay,
      scope: rootScope,
      cancellation: CancellationSignal._(),
      overrides: const <_ServiceIdentity, Object>{},
      locals: const <Object, Object>{},
      observation: observation,
      cleanupFailureReporter: null,
    );
    final child = Runtime._(context, _cleanupFailureObserver, _observers);
    final children = _childrenOf(this);
    children.add(child);

    rootScope.addFinalizer((_) {
      children.remove(child);
    });

    try {
      await _installExecutionModule(module, context);

      if (_state != RuntimeState.active ||
          child._state != RuntimeState.active) {
        throw const RuntimeClosedException();
      }

      return child;
    } catch (error, stackTrace) {
      try {
        await child._closeWith(ExitDefect<Object, Object>(error, stackTrace));
      } catch (closeError, closeStackTrace) {
        Error.throwWithStackTrace(
          CompositeDefect(
            primary: error,
            primaryStackTrace: stackTrace,
            secondary: closeError,
            secondaryStackTrace: closeStackTrace,
          ),
          stackTrace,
        );
      }

      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
