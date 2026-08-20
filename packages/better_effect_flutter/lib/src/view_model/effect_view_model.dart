part of '../../better_effect_flutter.dart';

/// Optional MVVM base class with concise, automatically disposed command
/// creation.
///
/// Existing ViewModel bases can instead use [EffectCommandOwner] directly.
abstract class EffectViewModel extends ChangeNotifier with EffectCommandOwner {
  EffectViewModel(this.commands);

  /// The scoped factory supplied by [BuildContext.effectCommands].
  @protected
  final EffectCommands commands;

  /// Create and own a command without input.
  @protected
  EffectCommand0<A, E> command<A extends Object, E extends Object>(
    Effect<A, E> Function() action, {
    CommandPolicy? policy,
    EffectCommandConcurrency? concurrency,
    bool keepPreviousData = true,
    String? debugLabel,
    VoidCallback? onCancel,
    EffectCommandStateObserver<A, E>? stateObserver,
    EffectCommandPolicyObserver? policyObserver,
  }) {
    return ownCommand(
      commands<A, E>(
        action,
        policy: policy,
        concurrency: concurrency,
        keepPreviousData: keepPreviousData,
        debugLabel: debugLabel,
        onCancel: onCancel,
        stateObserver: stateObserver,
        policyObserver: policyObserver,
      ),
    );
  }

  /// Create and own a command with one typed input.
  @protected
  EffectCommand<I, A, E>
  commandWithInput<I, A extends Object, E extends Object>(
    Effect<A, E> Function(I input) action, {
    CommandPolicy? policy,
    EffectCommandConcurrency? concurrency,
    bool keepPreviousData = true,
    String? debugLabel,
    VoidCallback? onCancel,
    EffectCommandStateObserver<A, E>? stateObserver,
    EffectCommandPolicyObserver? policyObserver,
  }) {
    return ownCommand(
      commands.withInput<I, A, E>(
        action,
        policy: policy,
        concurrency: concurrency,
        keepPreviousData: keepPreviousData,
        debugLabel: debugLabel,
        onCancel: onCancel,
        stateObserver: stateObserver,
        policyObserver: policyObserver,
      ),
    );
  }
}
