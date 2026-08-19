part of '../../better_effect_flutter.dart';

/// Creates, observes, and disposes a ViewModel at a Flutter composition
/// boundary without imposing Provider, Riverpod, BLoC, or another state package.
///
/// Applications already using a state-management package can create the
/// ViewModel with `context.effectCommands` in that package's normal provider.
final class EffectViewModelBuilder<T extends ChangeNotifier>
    extends StatefulWidget {
  const EffectViewModelBuilder({
    required this.create,
    required this.builder,
    this.child,
    this.recreateKey,
    this.disposeViewModel = true,
    this.onCreated,
    super.key,
  });

  final T Function(BuildContext context, EffectCommands commands) create;

  final Widget Function(BuildContext context, T viewModel, Widget? child)
  builder;

  final Widget? child;

  /// Explicitly recreate the ViewModel when this value changes.
  ///
  /// The `create` closure identity is deliberately ignored because inline Dart
  /// closures are recreated on ordinary parent rebuilds.
  final Object? recreateKey;

  /// Whether this widget owns and disposes the created ViewModel.
  final bool disposeViewModel;

  final void Function(T viewModel)? onCreated;

  @override
  State<EffectViewModelBuilder<T>> createState() =>
      _EffectViewModelBuilderState<T>();
}

final class _EffectViewModelBuilderState<T extends ChangeNotifier>
    extends State<EffectViewModelBuilder<T>> {
  T? _viewModel;
  EffectCommands? _commands;
  bool _ownsCurrentViewModel = false;

  @override
  Widget build(BuildContext context) {
    final viewModel = _viewModel;
    if (viewModel == null) {
      return const SizedBox.shrink();
    }

    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, child) {
        return widget.builder(context, viewModel, child);
      },
      child: widget.child,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final commands = context.watchEffectCommands();
    if (_viewModel != null && identical(commands, _commands)) {
      return;
    }

    _replaceViewModel(commands);
  }

  @override
  void didUpdateWidget(EffectViewModelBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.recreateKey != widget.recreateKey) {
      final commands = _commands;
      if (commands != null) {
        _replaceViewModel(commands);
      }
      return;
    }

    _ownsCurrentViewModel = widget.disposeViewModel;
  }

  @override
  void dispose() {
    final viewModel = _viewModel;
    if (viewModel != null && _ownsCurrentViewModel) {
      viewModel.dispose();
    }

    super.dispose();
  }

  void _replaceViewModel(EffectCommands commands) {
    final previous = _viewModel;
    if (previous != null && _ownsCurrentViewModel) {
      previous.dispose();
    }

    _commands = commands;
    final viewModel = widget.create(context, commands);
    _viewModel = viewModel;
    _ownsCurrentViewModel = widget.disposeViewModel;
    widget.onCreated?.call(viewModel);
  }
}
