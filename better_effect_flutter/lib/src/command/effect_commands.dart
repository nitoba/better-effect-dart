part of '../../better_effect_flutter.dart';

/// Creates [EffectCommand0] and [EffectCommand] instances bound to one
/// long-lived [Runtime].
///
/// A ViewModel normally receives this capability instead of receiving the
/// Runtime, Module, injector, or every repository it might use.
final class EffectCommands {
  const EffectCommands(this._runtime, {this.observer});

  final Runtime _runtime;

  /// Optional observer shared by every command created from this factory.
  final EffectCommandObserver? observer;

  /// Create a command without input.
  EffectCommand0<A, E> call<A extends Object, E extends Object>(
    Effect<A, E> Function() action, {
    EffectCommandConcurrency concurrency = EffectCommandConcurrency.drop,
    bool keepPreviousData = true,
    String? debugLabel,
    VoidCallback? onCancel,
    EffectCommandStateObserver<A, E>? stateObserver,
  }) {
    return EffectCommand0<A, E>._(
      _runtime,
      action,
      concurrency: concurrency,
      keepPreviousData: keepPreviousData,
      debugLabel: debugLabel,
      onCancel: onCancel,
      stateObserver: stateObserver,
      transitionObserver: observer,
    );
  }

  /// Create a command from an already-declared Effect.
  EffectCommand0<A, E> fromEffect<A extends Object, E extends Object>(
    Effect<A, E> effect, {
    EffectCommandConcurrency concurrency = EffectCommandConcurrency.drop,
    bool keepPreviousData = true,
    String? debugLabel,
    VoidCallback? onCancel,
    EffectCommandStateObserver<A, E>? stateObserver,
  }) {
    return call<A, E>(
      () => effect,
      concurrency: concurrency,
      keepPreviousData: keepPreviousData,
      debugLabel: debugLabel,
      onCancel: onCancel,
      stateObserver: stateObserver,
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
    EffectCommandConcurrency concurrency = EffectCommandConcurrency.drop,
    bool keepPreviousData = true,
    String? debugLabel,
    VoidCallback? onCancel,
    EffectCommandStateObserver<A, E>? stateObserver,
  }) {
    return EffectCommand<I, A, E>._(
      _runtime,
      action,
      concurrency: concurrency,
      keepPreviousData: keepPreviousData,
      debugLabel: debugLabel,
      onCancel: onCancel,
      stateObserver: stateObserver,
      transitionObserver: observer,
    );
  }
}
