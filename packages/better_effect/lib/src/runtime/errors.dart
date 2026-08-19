part of '../../better_effect.dart';

/// A finalizer failure captured while closing a [Scope].
typedef ReleaseFailure = ({Object error, StackTrace stackTrace});

/// Receives cleanup failures without changing the main Effect outcome.
typedef CleanupFailureObserver =
    FutureOr<void> Function(CleanupFailureDiagnostic diagnostic);

/// Describes a cleanup failure reported after an Effect outcome was known.
final class CleanupFailureDiagnostic {
  const CleanupFailureDiagnostic({
    required this.outcome,
    required this.error,
    required this.executionId,
    this.executionLabel,
  });

  /// The success, typed failure, defect, or interruption being cleaned up.
  final Exit<Object, Object> outcome;

  /// The scoped cleanup failures raised while closing the outcome's Scope.
  final ScopeReleaseException error;

  /// A caller-provided label for the execution, when available.
  final String? executionLabel;

  /// A monotonically increasing execution ID within a Runtime.
  ///
  /// The value zero identifies Runtime-level cleanup rather than an Effect
  /// execution.
  final int executionId;
}

/// Thrown when a [Module] contains more than one binding for the same service.
final class DuplicateServiceBindingException implements Exception {
  const DuplicateServiceBindingException({required this.serviceType, this.key});

  final Type serviceType;
  final String? key;

  @override
  String toString() {
    final suffix = key == null ? '' : ' using key "$key"';
    return 'Duplicate binding for $serviceType$suffix.';
  }
}

/// Identifies the Module resource whose acquisition failed.
///
/// [cause] keeps the backend or user-code exception intact. Dependency
/// containers can include their resolution path in that cause, while this
/// wrapper adds the resource identity that was being started.
final class ResourceAcquisitionException implements Exception {
  const ResourceAcquisitionException({
    required this.serviceType,
    required this.cause,
    required this.causeStackTrace,
    this.key,
  });

  final Type serviceType;
  final String? key;
  final Object cause;
  final StackTrace causeStackTrace;

  @override
  String toString() {
    final suffix = key == null ? '' : ' using key "$key"';
    return 'Failed to acquire Module resource $serviceType$suffix. Cause: $cause';
  }
}

/// Thrown when an operation is attempted after a [Runtime] stops accepting work.
final class RuntimeClosedException implements Exception {
  const RuntimeClosedException();

  @override
  String toString() => 'The better_effect Runtime is closed or closing.';
}

/// Thrown when new work is added to a [Scope] after closing starts.
final class ScopeClosedException implements Exception {
  const ScopeClosedException();

  @override
  String toString() => 'Cannot add work to a closed Scope.';
}

/// Aggregates one or more defects raised while releasing scoped resources.
final class ScopeReleaseException implements Exception {
  ScopeReleaseException(Iterable<ReleaseFailure> failures)
    : failures = List<ReleaseFailure>.unmodifiable(failures);

  final List<ReleaseFailure> failures;

  @override
  String toString() {
    return 'Scope release failed with ${failures.length} defect(s): '
        '${failures.map((failure) => failure.error).join(', ')}';
  }
}

/// Preserves a primary defect together with another defect raised during
/// cleanup.
final class CompositeDefect implements Exception {
  const CompositeDefect({
    required this.primary,
    required this.primaryStackTrace,
    required this.secondary,
    required this.secondaryStackTrace,
  });

  final Object primary;
  final StackTrace primaryStackTrace;
  final Object secondary;
  final StackTrace secondaryStackTrace;

  @override
  String toString() {
    return 'A defect occurred and cleanup raised another defect. '
        'Primary: $primary. Cleanup: $secondary.';
  }
}
