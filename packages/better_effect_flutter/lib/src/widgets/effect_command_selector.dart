part of '../../better_effect_flutter.dart';

/// Selects one strongly typed value from a Command state.
typedef EffectCommandStateSelector<A extends Object, E extends Object, S> =
    S Function(EffectCommandState<A, E> state);

/// Selects one strongly typed value from a read-only Command snapshot.
typedef EffectCommandSnapshotSelector<A extends Object, E extends Object, S> =
    S Function(EffectCommandSnapshot<A, E> snapshot);

/// Builds a subtree from a selected Command value.
typedef EffectCommandSelectedWidgetBuilder<S> =
    Widget Function(BuildContext context, S selected, Widget? child);

/// Compares previous and current selected values.
typedef EffectCommandSelectionEquals<S> = bool Function(S previous, S current);

/// Rebuilds only when a selected Command value changes.
///
/// The default constructor selects from [EffectCommandState]. Use
/// [EffectCommandSelector.snapshot] for queue/pending counts or the
/// latest Exit. Default equality uses Dart `==`; collections normally
/// need a custom [equals] callback.
final class EffectCommandSelector<A extends Object, E extends Object, S>
    extends StatefulWidget {
  const EffectCommandSelector({
    required ValueListenable<EffectCommandState<A, E>> command,
    required EffectCommandStateSelector<A, E, S> selector,
    required this.builder,
    this.equals,
    this.child,
    super.key,
  }) : _stateCommand = command,
       _stateSelector = selector,
       _snapshotCommand = null,
       _snapshotSelector = null;

  const EffectCommandSelector.snapshot({
    required EffectCommandBase<A, E> command,
    required EffectCommandSnapshotSelector<A, E, S> selector,
    required this.builder,
    this.equals,
    this.child,
    super.key,
  }) : _snapshotCommand = command,
       _snapshotSelector = selector,
       _stateCommand = null,
       _stateSelector = null;

  final ValueListenable<EffectCommandState<A, E>>? _stateCommand;
  final EffectCommandStateSelector<A, E, S>? _stateSelector;
  final EffectCommandBase<A, E>? _snapshotCommand;
  final EffectCommandSnapshotSelector<A, E, S>? _snapshotSelector;
  final EffectCommandSelectedWidgetBuilder<S> builder;
  final EffectCommandSelectionEquals<S>? equals;
  final Widget? child;

  Listenable get _listenable {
    return _snapshotCommand?.snapshot ?? _stateCommand!;
  }

  S _select() {
    final snapshotCommand = _snapshotCommand;
    if (snapshotCommand != null) {
      return _snapshotSelector!(snapshotCommand.snapshot.value);
    }
    return _stateSelector!(_stateCommand!.value);
  }

  @override
  State<EffectCommandSelector<A, E, S>> createState() =>
      _EffectCommandSelectorState<A, E, S>();
}

final class _EffectCommandSelectorState<A extends Object, E extends Object, S>
    extends State<EffectCommandSelector<A, E, S>> {
  late Listenable _listenable;
  late S _selected;

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _selected, widget.child);
  }

  @override
  void didUpdateWidget(EffectCommandSelector<A, E, S> oldWidget) {
    super.didUpdateWidget(oldWidget);

    final nextListenable = widget._listenable;
    if (!identical(_listenable, nextListenable)) {
      _listenable.removeListener(_handleChange);
      _listenable = nextListenable;
      _listenable.addListener(_handleChange);
    }

    // A parent rebuild can replace the selector or equality strategy.
    // Recompute immediately; this widget update already schedules build.
    _selected = widget._select();
  }

  @override
  void dispose() {
    _listenable.removeListener(_handleChange);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _listenable = widget._listenable;
    _selected = widget._select();
    _listenable.addListener(_handleChange);
  }

  void _handleChange() {
    final next = widget._select();
    final isEqual = widget.equals?.call(_selected, next) ?? _selected == next;
    if (isEqual) return;

    setState(() {
      _selected = next;
    });
  }
}
