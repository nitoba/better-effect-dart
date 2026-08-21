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
  Runtime? _runtime;
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

    final scope = BetterEffectScope.of(context);
    final runtime = scope.runtime;
    final commands = scope.commands;

    if (_viewModel != null && identical(runtime, _runtime)) {
      // Command observer configuration can replace the EffectCommands facade
      // without changing the effective Runtime. Keep the existing ViewModel in
      // that case, but remember the latest facade for an explicit recreateKey.
      _commands = commands;
      return;
    }

    _replaceViewModel(runtime, commands);
  }

  @override
  void didUpdateWidget(EffectViewModelBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.recreateKey != widget.recreateKey) {
      final runtime = _runtime;
      final commands = _commands;
      if (runtime != null && commands != null) {
        _replaceViewModel(runtime, commands);
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

  void _replaceViewModel(Runtime runtime, EffectCommands commands) {
    final previous = _viewModel;
    if (previous != null && _ownsCurrentViewModel) {
      previous.dispose();
    }

    _runtime = runtime;
    _commands = commands;
    final viewModel = widget.create(context, commands);
    _viewModel = viewModel;
    _ownsCurrentViewModel = widget.disposeViewModel;
    widget.onCreated?.call(viewModel);
  }
}
