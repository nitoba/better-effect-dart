part of '../../better_effect.dart';

typedef _NestedCleanupFailureReporter =
    Future<void> Function(
      ScopeReleaseException error,
      Exit<Object, Object> outcome,
      Scope scope,
    );

typedef _NestedScopeCloseResult<A extends Object, E extends Object> = ({
  Exit<A, E> outcome,
  bool cleanupFailed,
});

final class _ServiceIdentity {
  const _ServiceIdentity(this.type, this.key);

  final Type type;
  final String? key;

  @override
  bool operator ==(Object other) {
    return other is _ServiceIdentity && other.type == type && other.key == key;
  }

  @override
  int get hashCode => Object.hash(type, key);
}

final class _RuntimeContext {
  const _RuntimeContext({
    required this.backend,
    required this.scope,
    required this.cancellation,
    required this.overrides,
    required this.locals,
    required this.observation,
    required this.cleanupFailureReporter,
  });

  final ResolverBackend backend;
  final Scope scope;
  final CancellationSignal cancellation;
  final Map<_ServiceIdentity, Object> overrides;
  final Map<Object, Object> locals;
  final _ExecutionObservation? observation;
  final _NestedCleanupFailureReporter? cleanupFailureReporter;

  T _resolve<T extends Object>([ServiceKey<T>? key]) {
    final identity = _ServiceIdentity(T, key?._backendKey);
    final observers = observation;

    if (observers == null) {
      if (overrides.containsKey(identity)) {
        return overrides[identity]! as T;
      }

      return backend.resolve<T>(key: key?._backendKey);
    }

    final startedAt = DateTime.now();
    final source = overrides.containsKey(identity)
        ? ServiceResolutionSource.localOverride
        : ServiceResolutionSource.backend;

    try {
      final value = source == ServiceResolutionSource.localOverride
          ? overrides[identity]! as T
          : backend.resolve<T>(key: key?._backendKey);
      final completedAt = DateTime.now();

      observers.observers.serviceResolve(
        ServiceResolveEvent(
          context: observers.context(scope, locals),
          serviceType: T,
          serviceKey: key?.name,
          source: source,
          resolutionPath: <String>[_serviceRequestDisplay(T, key?.name)],
          startedAt: startedAt,
          completedAt: completedAt,
          duration: completedAt.difference(startedAt),
          error: null,
          stackTrace: null,
        ),
      );

      return value;
    } catch (error, stackTrace) {
      final completedAt = DateTime.now();
      observers.observers.serviceResolve(
        ServiceResolveEvent(
          context: observers.context(scope, locals),
          serviceType: T,
          serviceKey: key?.name,
          source: source,
          resolutionPath: _serviceResolutionPath(T, key?.name, error),
          startedAt: startedAt,
          completedAt: completedAt,
          duration: completedAt.difference(startedAt),
          error: error,
          stackTrace: stackTrace,
        ),
      );

      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  T _local<T extends Object>(EffectLocal<T> local) {
    if (locals.containsKey(local)) {
      return locals[local]! as T;
    }

    return local.initial;
  }

  Future<R> _acquireResource<R extends Object>({
    required FutureOr<R> Function() operation,
    required ResourceRelease<R> release,
    required Type serviceType,
    required String? serviceKey,
    required ResourceAcquisitionSource source,
  }) {
    final observers = observation;
    if (observers == null) {
      return scope._acquire(operation, release);
    }

    return _acquireObservedResource<R>(
      operation: operation,
      release: release,
      serviceType: serviceType,
      serviceKey: serviceKey,
      source: source,
      observers: observers,
    );
  }

  Future<R> _acquireObservedResource<R extends Object>({
    required FutureOr<R> Function() operation,
    required ResourceRelease<R> release,
    required Type serviceType,
    required String? serviceKey,
    required ResourceAcquisitionSource source,
    required _ExecutionObservation observers,
  }) async {
    final startedAt = DateTime.now();

    try {
      final resource = await scope._acquire(operation, (
        resource,
        outcome,
      ) async {
        final releaseStartedAt = DateTime.now();

        try {
          await Future<void>.sync(() => release(resource, outcome));
          final completedAt = DateTime.now();
          observers.observers.resourceRelease(
            ResourceReleaseEvent(
              context: observers.context(scope, locals),
              serviceType: serviceType,
              serviceKey: serviceKey,
              source: source,
              outcome: outcome,
              startedAt: releaseStartedAt,
              completedAt: completedAt,
              duration: completedAt.difference(releaseStartedAt),
              error: null,
              stackTrace: null,
            ),
          );
        } catch (error, stackTrace) {
          final completedAt = DateTime.now();
          observers.observers.resourceRelease(
            ResourceReleaseEvent(
              context: observers.context(scope, locals),
              serviceType: serviceType,
              serviceKey: serviceKey,
              source: source,
              outcome: outcome,
              startedAt: releaseStartedAt,
              completedAt: completedAt,
              duration: completedAt.difference(releaseStartedAt),
              error: error,
              stackTrace: stackTrace,
            ),
          );
          Error.throwWithStackTrace(error, stackTrace);
        }
      });
      final completedAt = DateTime.now();

      observers.observers.serviceAcquire(
        ServiceAcquireEvent(
          context: observers.context(scope, locals),
          serviceType: serviceType,
          serviceKey: serviceKey,
          source: source,
          startedAt: startedAt,
          completedAt: completedAt,
          duration: completedAt.difference(startedAt),
          error: null,
          stackTrace: null,
        ),
      );

      return resource;
    } catch (error, stackTrace) {
      final completedAt = DateTime.now();
      observers.observers.serviceAcquire(
        ServiceAcquireEvent(
          context: observers.context(scope, locals),
          serviceType: serviceType,
          serviceKey: serviceKey,
          source: source,
          startedAt: startedAt,
          completedAt: completedAt,
          duration: completedAt.difference(startedAt),
          error: error,
          stackTrace: stackTrace,
        ),
      );

      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _trackPhysical(Future<void> operation) {
    scope._trackPhysical(operation);
  }

  Future<_NestedScopeCloseResult<A, E>> _closeNestedScope<
    A extends Object,
    E extends Object
  >(Scope childScope, Exit<A, E> outcome) async {
    try {
      await childScope._close(outcome);
      return (outcome: outcome, cleanupFailed: false);
    } catch (error, stackTrace) {
      final releaseError = _asScopeReleaseException(error, stackTrace);
      final reporter = cleanupFailureReporter;
      if (reporter != null) {
        await reporter(releaseError, outcome, childScope);
      }

      if (outcome is ExitSuccess<A, E>) {
        return (
          outcome: ExitDefect<A, E>(error, stackTrace),
          cleanupFailed: true,
        );
      }

      if (outcome is ExitDefect<A, E>) {
        return (
          outcome: ExitDefect<A, E>(
            CompositeDefect(
              primary: outcome.defect,
              primaryStackTrace: outcome.stackTrace,
              secondary: error,
              secondaryStackTrace: stackTrace,
            ),
            outcome.stackTrace,
          ),
          cleanupFailed: true,
        );
      }

      return (outcome: outcome, cleanupFailed: true);
    }
  }

  _RuntimeContext _withScope(
    Scope childScope, {
    required CancellationSignal cancellation,
    required _ExecutionObservation? observation,
    _NestedCleanupFailureReporter? cleanupFailureReporter,
  }) {
    return _RuntimeContext(
      backend: backend,
      scope: childScope,
      cancellation: cancellation,
      overrides: overrides,
      locals: locals,
      observation: observation,
      cleanupFailureReporter:
          cleanupFailureReporter ?? this.cleanupFailureReporter,
    );
  }

  _RuntimeContext _withOverride<T extends Object>(
    T instance, {
    ServiceKey<T>? key,
  }) {
    final identity = _ServiceIdentity(T, key?._backendKey);

    return _RuntimeContext(
      backend: backend,
      scope: scope,
      cancellation: cancellation,
      overrides: <_ServiceIdentity, Object>{...overrides, identity: instance},
      locals: locals,
      observation: observation,
      cleanupFailureReporter: cleanupFailureReporter,
    );
  }

  _RuntimeContext _withLocals(Iterable<EffectLocalBinding> bindings) {
    final updated = <Object, Object>{...locals};
    for (final binding in bindings) {
      binding._writeLocal(updated);
    }

    return _RuntimeContext(
      backend: backend,
      scope: scope,
      cancellation: cancellation,
      overrides: overrides,
      locals: updated,
      observation: observation,
      cleanupFailureReporter: cleanupFailureReporter,
    );
  }
}

String _serviceRequestDisplay(Type serviceType, String? key) {
  return key == null ? '$serviceType' : '$serviceType[$key]';
}

List<String> _serviceResolutionPath(
  Type serviceType,
  String? key,
  Object error,
) {
  final requested = _serviceRequestDisplay(serviceType, key);
  final backendPath = switch (error) {
    UnregisteredInstance(:final classNames) => classNames,
    UnregisteredInstanceByKey(:final keys) => keys,
    _ => const <String>[],
  };

  if (backendPath.isEmpty) {
    return <String>[requested];
  }

  if (backendPath.first == requested) {
    return List<String>.of(backendPath);
  }

  return <String>[requested, ...backendPath];
}
