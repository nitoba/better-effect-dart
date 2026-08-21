part of '../../better_effect.dart';

/// Identifies the observer callback that raised an instrumentation error.
enum RuntimeObserverCallback {
  executionStart,
  executionEnd,
  serviceResolve,
  serviceAcquire,
  resourceRelease,
  interruption,
  retry,
  cleanupFailure,
}

/// Reports failures raised by [RuntimeObserver] callbacks.
typedef RuntimeObserverErrorHandler = void Function(RuntimeObserverError error);

/// How a service request was satisfied.
enum ServiceResolutionSource {
  /// The value came from [Effect.provide].
  localOverride,

  /// The request was delegated to the configured resolver backend.
  backend,
}

/// Which API acquired a scoped resource.
enum ResourceAcquisitionSource {
  /// The resource was declared by a root or execution-scoped [Module].
  module,

  /// The resource was acquired through [EffectContext.acquire].
  effect,
}

/// Which owner requested cooperative interruption.
enum InterruptionSource {
  /// [EffectExecution.interrupt] or a higher-level owner such as a Flutter
  /// Command requested interruption and published [ExitInterrupted].
  executionOwner,

  /// Runtime shutdown requested cancellation after its grace period. The
  /// running Effect still chooses whether to cross a cooperative boundary.
  runtimeShutdown,
}

/// Immutable execution and metadata projection shared by Runtime events.
final class RuntimeEventContext {
  RuntimeEventContext({
    required this.executionId,
    required this.executionLabel,
    required this.parentExecutionId,
    required this.scopeId,
    required Map<String, Object> localMetadata,
    this.runtimeId = 0,
    this.parentRuntimeId,
    this.runtimeLabel,
  }) : localMetadata = Map<String, Object>.unmodifiable(localMetadata);

  /// Zero identifies work owned by the root Runtime rather than one Effect.
  final int executionId;

  /// Optional label supplied to `execute`, `runExit`, or related APIs.
  final String? executionLabel;

  /// Reserved for structured child executions. It is null for current
  /// root-owned managed executions.
  final int? parentExecutionId;

  /// Stable identity of the Runtime that owns this event.
  final int runtimeId;

  /// Parent Runtime identity for a forked feature environment.
  final int? parentRuntimeId;

  /// Optional diagnostic label supplied when the child Runtime was forked.
  final String? runtimeLabel;

  /// Stable opaque identity for the owning Scope. The mutable Scope itself is
  /// never exposed to observers.
  final int scopeId;

  /// Selected [EffectLocal.metadata] values visible at the event boundary.
  final Map<String, Object> localMetadata;
}

/// Emitted synchronously immediately before an Effect runner starts.
final class ExecutionStartEvent {
  const ExecutionStartEvent({required this.context, required this.startedAt});

  final RuntimeEventContext context;
  final DateTime startedAt;
}

/// Emitted synchronously after physical work and Scope cleanup finish.
final class ExecutionEndEvent {
  const ExecutionEndEvent({
    required this.context,
    required this.startedAt,
    required this.completedAt,
    required this.duration,
    required this.outcome,
  });

  final RuntimeEventContext context;
  final DateTime startedAt;
  final DateTime completedAt;
  final Duration duration;

  /// The caller-visible logical outcome. Cleanup failures are reported
  /// separately and follow the Runtime's existing precedence rules.
  final Exit<Object, Object> outcome;
}

/// Describes one service-resolution attempt.
final class ServiceResolveEvent {
  ServiceResolveEvent({
    required this.context,
    required this.serviceType,
    required this.serviceKey,
    required this.source,
    required Iterable<String> resolutionPath,
    required this.startedAt,
    required this.completedAt,
    required this.duration,
    required this.error,
    required this.stackTrace,
  }) : resolutionPath = List<String>.unmodifiable(resolutionPath);

  final RuntimeEventContext context;
  final Type serviceType;

  /// Logical [ServiceKey.name], not a backend-specific key encoding.
  final String? serviceKey;

  final ServiceResolutionSource source;

  /// Human-readable request path. AutoInjector missing-service errors retain
  /// their constructor/key path; successful requests contain the requested
  /// service as the first segment.
  final List<String> resolutionPath;

  final DateTime startedAt;
  final DateTime completedAt;
  final Duration duration;
  final Object? error;
  final StackTrace? stackTrace;

  bool get succeeded => error == null;
}

/// Describes acquisition of one Module or Effect resource.
final class ServiceAcquireEvent {
  const ServiceAcquireEvent({
    required this.context,
    required this.serviceType,
    required this.serviceKey,
    required this.source,
    required this.startedAt,
    required this.completedAt,
    required this.duration,
    required this.error,
    required this.stackTrace,
  });

  final RuntimeEventContext context;
  final Type serviceType;
  final String? serviceKey;
  final ResourceAcquisitionSource source;
  final DateTime startedAt;
  final DateTime completedAt;
  final Duration duration;
  final Object? error;
  final StackTrace? stackTrace;

  bool get succeeded => error == null;
}

/// Describes release of one Module or Effect resource.
final class ResourceReleaseEvent {
  const ResourceReleaseEvent({
    required this.context,
    required this.serviceType,
    required this.serviceKey,
    required this.source,
    required this.outcome,
    required this.startedAt,
    required this.completedAt,
    required this.duration,
    required this.error,
    required this.stackTrace,
  });

  final RuntimeEventContext context;
  final Type serviceType;
  final String? serviceKey;
  final ResourceAcquisitionSource source;
  final Exit<Object, Object> outcome;
  final DateTime startedAt;
  final DateTime completedAt;
  final Duration duration;
  final Object? error;
  final StackTrace? stackTrace;

  bool get succeeded => error == null;
}

/// Emitted once when a managed execution first receives cancellation.
final class InterruptionEvent {
  const InterruptionEvent({
    required this.context,
    required this.timestamp,
    required this.reason,
    required this.source,
    required this.publishesLogicalInterruption,
  });

  final RuntimeEventContext context;
  final DateTime timestamp;
  final Object? reason;
  final InterruptionSource source;

  /// True for owner interruption, false for a shutdown cancellation signal that
  /// leaves the current logical outcome to the cooperative Effect.
  final bool publishesLogicalInterruption;
}

/// Why a retry loop continued or stopped after one attempt.
enum RetryDecision {
  retryScheduled,
  succeeded,
  policyStopped,
  failureRejected,
  interrupted,
  defect,
  cleanupFailed,
}

/// Immutable projection of one retry decision.
final class RetryEvent {
  const RetryEvent({
    required this.context,
    required this.timestamp,
    required this.attempt,
    required this.policyType,
    required this.decision,
    required this.previousFailure,
    required this.plannedDelay,
    required this.defect,
    required this.stackTrace,
  });

  final RuntimeEventContext context;
  final DateTime timestamp;
  final int attempt;
  final Type policyType;
  final RetryDecision decision;
  final Object? previousFailure;
  final Duration? plannedDelay;
  final Object? defect;
  final StackTrace? stackTrace;

  bool get willRetry => decision == RetryDecision.retryScheduled;
}

/// Runtime-observer projection of an existing cleanup diagnostic.
final class CleanupFailureEvent {
  const CleanupFailureEvent({
    required this.context,
    required this.timestamp,
    required this.diagnostic,
  });

  final RuntimeEventContext context;
  final DateTime timestamp;
  final CleanupFailureDiagnostic diagnostic;
}

/// A callback failure that was isolated from execution semantics.
final class RuntimeObserverError {
  const RuntimeObserverError({
    required this.observer,
    required this.callback,
    required this.event,
    required this.error,
    required this.stackTrace,
  });

  final RuntimeObserver observer;
  final RuntimeObserverCallback callback;
  final Object event;
  final Object error;
  final StackTrace stackTrace;
}

/// SDK-neutral, synchronous Runtime instrumentation.
///
/// Callbacks run in registration order. They must return quickly and enqueue
/// asynchronous export work themselves. Every callback is isolated: throwing
/// never replaces an Effect outcome or prevents later observers from running.
abstract base class RuntimeObserver {
  const RuntimeObserver();

  void onExecutionStart(ExecutionStartEvent event) {}

  void onExecutionEnd(ExecutionEndEvent event) {}

  void onServiceResolve(ServiceResolveEvent event) {}

  void onServiceAcquire(ServiceAcquireEvent event) {}

  void onResourceRelease(ResourceReleaseEvent event) {}

  void onInterruption(InterruptionEvent event) {}

  void onRetry(RetryEvent event) {}

  void onCleanupFailure(CleanupFailureEvent event) {}
}

final class _RuntimeObservers {
  _RuntimeObservers._(Iterable<RuntimeObserver> observers, this.errorHandler)
    : observers = List<RuntimeObserver>.unmodifiable(observers);

  static _RuntimeObservers? create(
    Iterable<RuntimeObserver> observers,
    RuntimeObserverErrorHandler? errorHandler,
  ) {
    final values = List<RuntimeObserver>.of(observers);
    return values.isEmpty ? null : _RuntimeObservers._(values, errorHandler);
  }

  final List<RuntimeObserver> observers;
  final RuntimeObserverErrorHandler? errorHandler;

  void executionStart(ExecutionStartEvent event) {
    _notify(
      RuntimeObserverCallback.executionStart,
      event,
      (observer) => observer.onExecutionStart(event),
    );
  }

  void executionEnd(ExecutionEndEvent event) {
    _notify(
      RuntimeObserverCallback.executionEnd,
      event,
      (observer) => observer.onExecutionEnd(event),
    );
  }

  void serviceResolve(ServiceResolveEvent event) {
    _notify(
      RuntimeObserverCallback.serviceResolve,
      event,
      (observer) => observer.onServiceResolve(event),
    );
  }

  void serviceAcquire(ServiceAcquireEvent event) {
    _notify(
      RuntimeObserverCallback.serviceAcquire,
      event,
      (observer) => observer.onServiceAcquire(event),
    );
  }

  void resourceRelease(ResourceReleaseEvent event) {
    _notify(
      RuntimeObserverCallback.resourceRelease,
      event,
      (observer) => observer.onResourceRelease(event),
    );
  }

  void interruption(InterruptionEvent event) {
    _notify(
      RuntimeObserverCallback.interruption,
      event,
      (observer) => observer.onInterruption(event),
    );
  }

  void retry(RetryEvent event) {
    _notify(
      RuntimeObserverCallback.retry,
      event,
      (observer) => observer.onRetry(event),
    );
  }

  void cleanupFailure(CleanupFailureEvent event) {
    _notify(
      RuntimeObserverCallback.cleanupFailure,
      event,
      (observer) => observer.onCleanupFailure(event),
    );
  }

  void _notify(
    RuntimeObserverCallback callback,
    Object event,
    void Function(RuntimeObserver observer) invoke,
  ) {
    for (final observer in observers) {
      try {
        invoke(observer);
      } catch (error, stackTrace) {
        final handler = errorHandler;
        if (handler == null) {
          continue;
        }

        try {
          handler(
            RuntimeObserverError(
              observer: observer,
              callback: callback,
              event: event,
              error: error,
              stackTrace: stackTrace,
            ),
          );
        } catch (_) {
          // Instrumentation error reporting is best-effort too.
        }
      }
    }
  }
}

final class _ExecutionObservation {
  _ExecutionObservation({
    required this.observers,
    required this.executionId,
    required this.executionLabel,
    required this.parentExecutionId,
    this.runtimeId,
    this.parentRuntimeId,
    this.runtimeLabel,
    required this.startedAt,
    required Map<String, Object> initialMetadata,
  }) : initialMetadata = Map<String, Object>.unmodifiable(initialMetadata);

  final _RuntimeObservers observers;
  final int executionId;
  final String? executionLabel;
  final int? parentExecutionId;
  final int? runtimeId;
  final int? parentRuntimeId;
  final String? runtimeLabel;
  final DateTime startedAt;
  final Map<String, Object> initialMetadata;

  RuntimeEventContext context(Scope scope, Map<Object, Object> locals) {
    final hierarchy = _runtimeMetadataForScope(scope);
    return RuntimeEventContext(
      executionId: executionId,
      executionLabel: executionLabel,
      parentExecutionId: parentExecutionId,
      runtimeId: runtimeId ?? hierarchy.runtimeId,
      parentRuntimeId: parentRuntimeId ?? hierarchy.parentRuntimeId,
      runtimeLabel: runtimeLabel ?? hierarchy.runtimeLabel,
      scopeId: identityHashCode(scope),
      localMetadata: <String, Object>{
        ...initialMetadata,
        ..._effectLocalMetadata(locals),
      },
    );
  }
}
