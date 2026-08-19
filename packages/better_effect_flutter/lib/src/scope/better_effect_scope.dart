part of '../../better_effect_flutter.dart';

/// Exposes a long-lived better_effect [Runtime] and its [EffectCommands] to a
/// Flutter subtree.
///
/// Business code should request dependencies through `use<T>()` inside an
/// Effect. This scope exists so Flutter composition boundaries can create
/// ViewModels and execute Commands without a global injector.
final class BetterEffectScope extends InheritedWidget {
  const BetterEffectScope({
    required this.runtime,
    required this.commands,
    required super.child,
    super.key,
  });

  final Runtime runtime;

  final EffectCommands commands;

  static BetterEffectScope? maybeOf(
    BuildContext context, {
    bool listen = true,
  }) {
    return listen
        ? context.dependOnInheritedWidgetOfExactType<BetterEffectScope>()
        : context.getInheritedWidgetOfExactType<BetterEffectScope>();
  }

  static BetterEffectScope of(
    BuildContext context, {
    bool listen = true,
  }) {
    final scope = maybeOf(context, listen: listen);
    if (scope != null) {
      return scope;
    }

    throw FlutterError.fromParts(<DiagnosticsNode>[
      ErrorSummary('No BetterEffectScope found in this BuildContext.'),
      ErrorDescription(
        'Wrap the application with runBetterEffectApp, BetterEffectProvider, '
        'or BetterEffectBootstrap before reading effectCommands or effectRuntime.',
      ),
      ErrorHint(
        'Views should normally receive a ViewModel. Resolve repositories and '
        'services only inside Effect.result through use<T>().',
      ),
      context.describeElement('The context used was'),
    ]);
  }

  @override
  bool updateShouldNotify(BetterEffectScope oldWidget) {
    return !identical(runtime, oldWidget.runtime) ||
        !identical(commands, oldWidget.commands);
  }
}
