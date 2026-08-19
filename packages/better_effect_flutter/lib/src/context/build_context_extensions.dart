part of '../../better_effect_flutter.dart';

/// Flutter accessors for the nearest [BetterEffectScope].
extension BetterEffectBuildContext on BuildContext {
  /// The scoped command factory intended for ViewModel construction.
  ///
  /// This is a non-listening read, which makes it safe to use from object
  /// factories such as `ChangeNotifierProvider.create`. Application runtimes
  /// are normally stable for the lifetime of the subtree. Framework adapters
  /// that need to react to scope replacement can use [watchEffectCommands].
  EffectCommands get effectCommands {
    return BetterEffectScope.of(this, listen: false).commands;
  }

  /// Listen to the nearest scope and return its command factory.
  ///
  /// Most Views do not need this. It is primarily used by lifecycle adapters
  /// such as [EffectViewModelBuilder].
  EffectCommands watchEffectCommands() {
    return BetterEffectScope.of(this).commands;
  }

  /// The scoped Runtime.
  ///
  /// Prefer [effectCommands] in ViewModels. Direct Runtime access is useful at
  /// integration boundaries and for state-management adapters. This getter does
  /// not subscribe the caller to scope replacement.
  Runtime get effectRuntime {
    return BetterEffectScope.of(this, listen: false).runtime;
  }

  /// Execute an Effect and return its typed Result.
  Future<ResultDart<A, E>> runEffect<
    A extends Object,
    E extends Object
  >(
    Effect<A, E> effect,
  ) {
    return BetterEffectScope.of(this, listen: false).runtime.run(effect);
  }

  /// Execute an Effect while preserving expected failures and defects in Exit.
  Future<Exit<A, E>> runEffectExit<
    A extends Object,
    E extends Object
  >(
    Effect<A, E> effect,
  ) {
    return BetterEffectScope.of(this, listen: false).runtime.runExit(effect);
  }

  /// Resolve a service at a Flutter composition boundary.
  ///
  /// Views should normally communicate only with their ViewModel. This method is
  /// intended for route/provider factories, framework adapters, and other object
  /// construction boundaries—not for business logic inside Widgets.
  T readEffectService<T extends Object>([ServiceKey<T>? key]) {
    return BetterEffectScope.of(
      this,
      listen: false,
    ).runtime.services.get<T>(key);
  }
}
