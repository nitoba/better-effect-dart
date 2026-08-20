part of '../../better_effect_flutter.dart';

/// Builds a Widget from the current typed command state.
typedef EffectCommandWidgetBuilder<A extends Object, E extends Object> =
    Widget Function(
      BuildContext context,
      EffectCommandState<A, E> state,
      Widget? child,
    );

/// Decides whether one state transition should rebuild the subtree.
typedef EffectCommandBuildWhen<A extends Object, E extends Object> =
    bool Function(
      EffectCommandState<A, E> previous,
      EffectCommandState<A, E> current,
    );

/// A typed Command-state builder with optional transition filtering.
///
/// With no [buildWhen], behavior remains equivalent to a typed
/// [ValueListenableBuilder]. A rejected transition still becomes the
/// next comparison baseline, but the rendered state remains the last
/// state accepted for building.
final class EffectCommandBuilder<A extends Object, E extends Object>
    extends StatefulWidget {
  const EffectCommandBuilder({
    required this.command,
    required this.builder,
    this.buildWhen,
    this.child,
    super.key,
  });

  final ValueListenable<EffectCommandState<A, E>> command;
  final EffectCommandWidgetBuilder<A, E> builder;
  final EffectCommandBuildWhen<A, E>? buildWhen;
  final Widget? child;

  @override
  State<EffectCommandBuilder<A, E>> createState() =>
      _EffectCommandBuilderState<A, E>();
}

final class _EffectCommandBuilderState<A extends Object, E extends Object>
    extends State<EffectCommandBuilder<A, E>> {
  late EffectCommandState<A, E> _latest;
  late EffectCommandState<A, E> _built;

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _built, widget.child);
  }

  @override
  void didUpdateWidget(EffectCommandBuilder<A, E> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.command, widget.command)) return;

    oldWidget.command.removeListener(_handleChange);
    _latest = widget.command.value;
    _built = _latest;
    widget.command.addListener(_handleChange);
  }

  @override
  void dispose() {
    widget.command.removeListener(_handleChange);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _latest = widget.command.value;
    _built = _latest;
    widget.command.addListener(_handleChange);
  }

  void _handleChange() {
    final previous = _latest;
    final current = widget.command.value;
    _latest = current;

    if (!(widget.buildWhen?.call(previous, current) ?? true)) {
      return;
    }

    setState(() {
      _built = current;
    });
  }
}
