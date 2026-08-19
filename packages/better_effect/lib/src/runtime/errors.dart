part of '../../better_effect.dart';

/// A finalizer failure captured while closing a [Scope].
typedef ReleaseFailure = ({Object error, StackTrace stackTrace});

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

/// Thrown when an operation is attempted after a [Runtime] stops accepting work.
final class RuntimeClosedException implements Exception {
  const RuntimeClosedException();

  @override
  String toString() => 'The better_effect Runtime is closed or closing.';
}

/// Thrown when a finalizer is added to a scope that is already closed.
final class ScopeClosedException implements Exception {
  const ScopeClosedException();

  @override
  String toString() => 'Cannot add a finalizer to a closed Scope.';
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
