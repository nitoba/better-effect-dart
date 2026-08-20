part of '../../better_effect_flutter.dart';

/// Places an existing [Runtime] in the Flutter tree with explicit ownership.
///
/// The default constructor is application-owned for migration compatibility: it
/// closes on widget disposal and coordinates supported application-exit events.
/// Use [BetterEffectProvider.value] for a Runtime owned by another boundary, or
/// set [ownership] to [BetterEffectRuntimeOwnership.widget] for a feature root
/// that should only follow widget lifetime.
final class BetterEffectProvider extends StatefulWidget {
  const BetterEffectProvider({
    required this.runtime,
    required this.child,
    this.observer,
    this.ownership = BetterEffectRuntimeOwnership.application,
    this.lifecyclePolicy = const BetterEffectLifecyclePolicy.application(),
    @Deprecated(
      'Use lifecyclePolicy.closeOnWidgetDispose. '
      'This compatibility parameter will be removed before 1.0.',
    )
    bool? closeRuntimeOnDispose,
    @Deprecated(
      'Use ownership and lifecyclePolicy.closeOnApplicationExit. '
      'This compatibility parameter will be removed before 1.0.',
    )
    bool? closeRuntimeOnDetach,
    this.onRuntimeCloseError,
    super.key,
  }) : assert(
         ownership != BetterEffectRuntimeOwnership.external,
         'Use BetterEffectProvider.value for an externally owned Runtime.',
       ),
       _legacyCloseOnWidgetDispose = closeRuntimeOnDispose,
       _legacyCloseOnApplicationExit = closeRuntimeOnDetach;

  const BetterEffectProvider.value({
    required this.runtime,
    required this.child,
    this.observer,
    this.onRuntimeCloseError,
    super.key,
  }) : ownership = BetterEffectRuntimeOwnership.external,
       lifecyclePolicy = const BetterEffectLifecyclePolicy.external(),
       _legacyCloseOnWidgetDispose = null,
       _legacyCloseOnApplicationExit = null;

  final Runtime runtime;

  final Widget child;

  final EffectCommandObserver? observer;

  /// Who is responsible for closing [runtime].
  final BetterEffectRuntimeOwnership ownership;

  /// Shutdown triggers and cooperative interruption options for owned Runtimes.
  final BetterEffectLifecyclePolicy lifecyclePolicy;

  final bool? _legacyCloseOnWidgetDispose;
  final bool? _legacyCloseOnApplicationExit;

  final void Function(Object error, StackTrace stackTrace)? onRuntimeCloseError;

  BetterEffectLifecyclePolicy get _effectiveLifecyclePolicy {
    if (ownership == BetterEffectRuntimeOwnership.external) {
      return const BetterEffectLifecyclePolicy.external();
    }

    return BetterEffectLifecyclePolicy(
      closeOnWidgetDispose:
          _legacyCloseOnWidgetDispose ?? lifecyclePolicy.closeOnWidgetDispose,
      closeOnApplicationExit:
          _legacyCloseOnApplicationExit ??
          lifecyclePolicy.closeOnApplicationExit,
      interruptExecutionsBeforeClose:
          lifecyclePolicy.interruptExecutionsBeforeClose,
      gracePeriod: lifecyclePolicy.gracePeriod,
    );
  }

  _BetterEffectCloseConfiguration get _closeConfiguration {
    return _BetterEffectCloseConfiguration(
      policy: _effectiveLifecyclePolicy,
      onError: onRuntimeCloseError,
      ownerDescription: 'a BetterEffectProvider Runtime',
    );
  }

  @override
  State<BetterEffectProvider> createState() => _BetterEffectProviderState();
}

final class _BetterEffectProviderState extends State<BetterEffectProvider> {
  final Map<Runtime, Future<void>> _closeOperations = <Runtime, Future<void>>{};

  Runtime? _runtime;
  EffectCommands? _commands;
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _publish(widget.runtime);
    _configureLifecycleListener();
  }

  @override
  void didUpdateWidget(BetterEffectProvider oldWidget) {
    super.didUpdateWidget(oldWidget);

    final runtimeChanged = !identical(oldWidget.runtime, widget.runtime);
    final observerChanged = !identical(oldWidget.observer, widget.observer);
    final lifecycleChanged =
        oldWidget.ownership != widget.ownership ||
        oldWidget.lifecyclePolicy != widget.lifecyclePolicy ||
        oldWidget._legacyCloseOnWidgetDispose !=
            widget._legacyCloseOnWidgetDispose ||
        oldWidget._legacyCloseOnApplicationExit !=
            widget._legacyCloseOnApplicationExit;

    if (runtimeChanged) {
      _publish(widget.runtime);

      final oldPolicy = oldWidget._effectiveLifecyclePolicy;
      if (oldWidget.ownership != BetterEffectRuntimeOwnership.external &&
          oldPolicy.closeOnWidgetDispose) {
        unawaited(
          _closeRuntime(oldWidget.runtime, oldWidget._closeConfiguration),
        );
      }
    } else if (observerChanged && _runtime != null) {
      _commands = EffectCommands(_runtime!, observer: widget.observer);
    }

    if (lifecycleChanged) {
      _configureLifecycleListener();
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _runtime;
    final commands = _commands;

    if (runtime == null || commands == null) {
      return const SizedBox.shrink();
    }

    return BetterEffectScope(
      runtime: runtime,
      commands: commands,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();

    final runtime = _runtime;
    _runtime = null;
    _commands = null;

    final policy = widget._effectiveLifecyclePolicy;
    if (runtime != null &&
        widget.ownership != BetterEffectRuntimeOwnership.external &&
        policy.closeOnWidgetDispose) {
      unawaited(_closeRuntime(runtime, widget._closeConfiguration));
    }

    super.dispose();
  }

  void _publish(Runtime runtime) {
    _runtime = runtime;
    _commands = EffectCommands(runtime, observer: widget.observer);
  }

  void _configureLifecycleListener() {
    _lifecycleListener?.dispose();

    final policy = widget._effectiveLifecyclePolicy;
    final listensForApplicationExit =
        widget.ownership == BetterEffectRuntimeOwnership.application &&
        policy.closeOnApplicationExit;

    _lifecycleListener = listensForApplicationExit
        ? AppLifecycleListener(
            onDetach: () {
              unawaited(_closeForApplicationExit());
            },
            onExitRequested: () async {
              await _closeForApplicationExit();
              return AppExitResponse.exit;
            },
          )
        : null;
  }

  Future<void> _closeForApplicationExit() {
    final runtime = _runtime;
    if (runtime == null) {
      return Future<void>.value();
    }

    if (mounted) {
      setState(() {
        _runtime = null;
        _commands = null;
      });
    } else {
      _runtime = null;
      _commands = null;
    }

    return _closeRuntime(runtime, widget._closeConfiguration);
  }

  Future<void> _closeRuntime(
    Runtime runtime,
    _BetterEffectCloseConfiguration configuration,
  ) {
    return _closeOperations.putIfAbsent(
      runtime,
      () => configuration.close(runtime),
    );
  }
}
