part of '../../better_effect_flutter.dart';

/// Builds a Widget from the current typed command state.
typedef EffectCommandWidgetBuilder<A extends Object, E extends Object> =
    Widget Function(
      BuildContext context,
      EffectCommandState<A, E> state,
      Widget? child,
    );

/// A typed [ValueListenableBuilder] specialized for Effect command states.
final class EffectCommandBuilder<A extends Object, E extends Object>
    extends StatelessWidget {
  const EffectCommandBuilder({
    required this.command,
    required this.builder,
    this.child,
    super.key,
  });

  final ValueListenable<EffectCommandState<A, E>> command;
  final EffectCommandWidgetBuilder<A, E> builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EffectCommandState<A, E>>(
      valueListenable: command,
      builder: builder,
      child: child,
    );
  }
}
