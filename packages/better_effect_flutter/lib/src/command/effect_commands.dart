part of '../../better_effect_flutter.dart';

/// Creates [EffectCommand0] and [EffectCommand] instances bound to one
/// long-lived [Runtime].
///
/// A ViewModel normally receives this capability instead of receiving the
/// Runtime, Module, injector, or every repository it might use.
final class EffectCommands {
  const EffectCommands(this._runtime, {this.observer, this.policyObserver});

  final Runtime _runtime;

  /// Optional state-transition observer shared by every created Command.
  final EffectCommandObserver? observer;

  /// Optional policy-decision observer shared by every created Command.
  final EffectCommandPolicyObserver? policyObserver;

  /// Create a command without input.
  EffectCommand0<A, E> call<A extends Object, E extends Object>(
    Effect<A, E> Function() action, {
    CommandPolicy? policy,
    EffectCommandConcurrency? concurrency,
    bool keepPreviousData = true,
    String? debugLabel,
    VoidCallback? onCancel,
    EffectCommandStateObserver<A, E>? stateObserver,
    EffectCommandPolicyObserver? policyObserver,
  }) {
    final resolvedPolicy = _resolveCommandPolicy(
      policy: policy,
      concurrency: concurrency,
      acceptsInput: false,
    );
    return EffectCommand0<A, E>._(
      _runtime,
      action,
      policy: resolvedPolicy,
      keepPreviousData: keepPreviousData,
      debugLabel: debugLabel,
      onCancel: onCancel,
      stateObserver: stateObserver,
      transitionObserver: observer,
      sharedPolicyObserver: this.policyObserver,
      policyObserver: policyObserver,
    );
  }

  /// Create a command from an already-declared Effect.
  EffectCommand0<A, E> fromEffect<A extends Object, E extends Object>(
    Effect<A, E> effect, {
    CommandPolicy? policy,
    EffectCommandConcurrency? concurrency,
    bool keepPreviousData = true,
    String? debugLabel,
    VoidCallback? onCancel,
    EffectCommandStateObserver<A, E>? stateObserver,
    EffectCommandPolicyObserver? policyObserver,
  }) {
    return call<A, E>(
      () => effect,
      policy: policy,
      concurrency: concurrency,
      keepPreviousData: keepPreviousData,
      debugLabel: debugLabel,
      onCancel: onCancel,
      stateObserver: stateObserver,
      policyObserver: policyObserver,
    );
  }

  /// Create a command with one typed input.
  ///
  /// Prefer a named record when an action needs multiple values:
  ///
  /// ```dart
  /// commands.withInput<
  ///   ({String email, String password}),
  ///   Session,
  ///   AuthFailure
  /// >(_login);
  /// ```
  EffectCommand<I, A, E> withInput<I, A extends Object, E extends Object>(
    Effect<A, E> Function(I input) action, {
    CommandPolicy? policy,
    EffectCommandConcurrency? concurrency,
    bool keepPreviousData = true,
    String? debugLabel,
    VoidCallback? onCancel,
    EffectCommandStateObserver<A, E>? stateObserver,
    EffectCommandPolicyObserver? policyObserver,
  }) {
    final resolvedPolicy = _resolveCommandPolicy(
      policy: policy,
      concurrency: concurrency,
      acceptsInput: true,
    );
    return EffectCommand<I, A, E>._(
      _runtime,
      action,
      policy: resolvedPolicy,
      keepPreviousData: keepPreviousData,
      debugLabel: debugLabel,
      onCancel: onCancel,
      stateObserver: stateObserver,
      transitionObserver: observer,
      sharedPolicyObserver: this.policyObserver,
      policyObserver: policyObserver,
    );
  }
}

CommandPolicy _resolveCommandPolicy({
  required CommandPolicy? policy,
  required EffectCommandConcurrency? concurrency,
  required bool acceptsInput,
}) {
  if (policy != null && concurrency != null) {
    throw ArgumentError(
      'Use either policy or concurrency, not both. The concurrency parameter '
      'exists only for migration compatibility.',
    );
  }

  final resolved =
      policy ?? concurrency?.asPolicy ?? const CommandPolicy.drop();
  resolved._validate(acceptsInput: acceptsInput);
  return resolved;
}
