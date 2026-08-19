part of '../../better_effect_flutter.dart';

/// Places an existing [Runtime] in the Flutter tree and optionally owns it.
///
/// The default constructor owns the Runtime and closes it when the provider is
/// disposed or the Flutter view is detached. Use [BetterEffectProvider.value]
/// when another object owns the Runtime lifecycle.
final class BetterEffectProvider extends StatefulWidget {
  const BetterEffectProvider({
    required this.runtime,
    required this.child,
    this.observer,
    this.closeRuntimeOnDispose = true,
    this.closeRuntimeOnDetach = true,
    this.onRuntimeCloseError,
    super.key,
  });

  const BetterEffectProvider.value({
    required this.runtime,
    required this.child,
    this.observer,
    this.onRuntimeCloseError,
    super.key,
  }) : closeRuntimeOnDispose = false,
       closeRuntimeOnDetach = false;

  final Runtime runtime;

  final Widget child;

  final EffectCommandObserver? observer;

  final bool closeRuntimeOnDispose;

  final bool closeRuntimeOnDetach;

  final void Function(Object error, StackTrace stackTrace)? onRuntimeCloseError;

  @override
  State<BetterEffectProvider> createState() => _BetterEffectProviderState();
}

final class _BetterEffectProviderState extends State<BetterEffectProvider> {
  late EffectCommands _commands;
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _commands = EffectCommands(widget.runtime, observer: widget.observer);
    _configureLifecycleListener();
  }

  @override
  void didUpdateWidget(BetterEffectProvider oldWidget) {
    super.didUpdateWidget(oldWidget);

    final runtimeChanged = !identical(oldWidget.runtime, widget.runtime);
    final observerChanged = !identical(oldWidget.observer, widget.observer);

    if (runtimeChanged || observerChanged) {
      _commands = EffectCommands(widget.runtime, observer: widget.observer);
    }

    if (runtimeChanged && oldWidget.closeRuntimeOnDispose) {
      unawaited(_closeRuntime(oldWidget.runtime));
    }

    if (oldWidget.closeRuntimeOnDetach != widget.closeRuntimeOnDetach) {
      _configureLifecycleListener();
    }
  }

  void _configureLifecycleListener() {
    _lifecycleListener?.dispose();
    _lifecycleListener = widget.closeRuntimeOnDetach
        ? AppLifecycleListener(
            onDetach: () {
              unawaited(_closeRuntime(widget.runtime));
            },
          )
        : null;
  }

  @override
  Widget build(BuildContext context) {
    return BetterEffectScope(
      runtime: widget.runtime,
      commands: _commands,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();

    if (widget.closeRuntimeOnDispose) {
      unawaited(_closeRuntime(widget.runtime));
    }

    super.dispose();
  }

  Future<void> _closeRuntime(Runtime runtime) async {
    try {
      await runtime.close();
    } catch (error, stackTrace) {
      final handler = widget.onRuntimeCloseError;
      if (handler != null) {
        handler(error, stackTrace);
        return;
      }

      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'better_effect_flutter',
          context: ErrorDescription(
            'while closing a BetterEffectProvider Runtime',
          ),
        ),
      );
    }
  }
}
