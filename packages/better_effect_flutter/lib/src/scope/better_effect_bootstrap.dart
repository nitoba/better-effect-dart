part of '../../better_effect_flutter.dart';

/// Creates a fresh resolver backend whenever [BetterEffectBootstrap] starts or
/// retries.
typedef BetterEffectBackendFactory = ResolverBackend Function();

/// Builds the application subtree after the Runtime starts.
typedef BetterEffectBootstrapBuilder = Widget Function(BuildContext context);

/// Builds a startup error UI. Calling [retry] starts a fresh Runtime.
typedef BetterEffectBootstrapErrorBuilder =
    Widget Function(
      BuildContext context,
      Object error,
      StackTrace stackTrace,
      VoidCallback retry,
    );

/// Declaratively starts an application-owned [Runtime] inside Flutter.
///
/// Prefer [runBetterEffectApp] when better_effect owns the application root.
/// Use this widget for add-to-app scenarios, tests, previews, or feature roots
/// that need asynchronous Runtime startup. The Runtime is removed from the tree
/// before any lifecycle-triggered close begins.
final class BetterEffectBootstrap extends StatefulWidget {
  const BetterEffectBootstrap({
    required this.module,
    required this.builder,
    this.backendFactory,
    this.observer,
    this.loadingBuilder,
    this.minimumLoadingDuration = Duration.zero,
    this.errorBuilder,
    this.restartKey,
    this.lifecyclePolicy = const BetterEffectLifecyclePolicy.application(),
    @Deprecated(
      'Use lifecyclePolicy.closeOnApplicationExit. '
      'This compatibility parameter will be removed before 1.0.',
    )
    bool? closeRuntimeOnDetach,
    this.onRuntimeCloseError,
    super.key,
  }) : _legacyCloseOnApplicationExit = closeRuntimeOnDetach;

  final Module module;

  final BetterEffectBootstrapBuilder builder;

  /// Creates the backend for each start attempt.
  ///
  /// A factory is used instead of a backend instance because a failed/retried
  /// bootstrap must not reuse an already committed or closed resolver.
  final BetterEffectBackendFactory? backendFactory;

  final EffectCommandObserver? observer;

  final WidgetBuilder? loadingBuilder;

  /// Minimum amount of time the loading UI remains visible.
  ///
  /// The duration starts after the first loading frame is presented.
  final Duration minimumLoadingDuration;

  final BetterEffectBootstrapErrorBuilder? errorBuilder;

  /// Changing this value restarts the Runtime even when [module] is identical.
  final Object? restartKey;

  /// Shutdown triggers and cooperative interruption options.
  final BetterEffectLifecyclePolicy lifecyclePolicy;

  final bool? _legacyCloseOnApplicationExit;

  final void Function(Object error, StackTrace stackTrace)? onRuntimeCloseError;

  BetterEffectLifecyclePolicy get _effectiveLifecyclePolicy {
    return BetterEffectLifecyclePolicy(
      closeOnWidgetDispose: lifecyclePolicy.closeOnWidgetDispose,
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
      ownerDescription: 'a BetterEffectBootstrap Runtime',
    );
  }

  @override
  State<BetterEffectBootstrap> createState() => _BetterEffectBootstrapState();
}

final class _BetterEffectBootstrapState extends State<BetterEffectBootstrap> {
  final Map<Runtime, Future<void>> _closeOperations = <Runtime, Future<void>>{};

  Runtime? _runtime;
  EffectCommands? _commands;
  Object? _error;
  StackTrace? _stackTrace;
  AppLifecycleListener? _lifecycleListener;
  int _generation = 0;

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final stackTrace = _stackTrace;

    if (error != null && stackTrace != null) {
      return widget.errorBuilder?.call(context, error, stackTrace, _retry) ??
          ErrorWidget(error);
    }

    final runtime = _runtime;
    final commands = _commands;

    if (runtime == null || commands == null) {
      return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
    }

    return BetterEffectScope(
      runtime: runtime,
      commands: commands,
      child: Builder(builder: widget.builder),
    );
  }

  @override
  void didUpdateWidget(BetterEffectBootstrap oldWidget) {
    super.didUpdateWidget(oldWidget);

    final lifecycleChanged =
        oldWidget.lifecyclePolicy != widget.lifecyclePolicy ||
        oldWidget._legacyCloseOnApplicationExit !=
            widget._legacyCloseOnApplicationExit;
    final shouldRestart =
        !identical(oldWidget.module, widget.module) ||
        !identical(oldWidget.backendFactory, widget.backendFactory) ||
        oldWidget.restartKey != widget.restartKey;

    if (lifecycleChanged) {
      _configureLifecycleListener();
    }

    if (shouldRestart) {
      unawaited(_restart(previousConfiguration: oldWidget._closeConfiguration));
      return;
    }

    if (!identical(oldWidget.observer, widget.observer) && _runtime != null) {
      _commands = EffectCommands(_runtime!, observer: widget.observer);
    }
  }

  @override
  void dispose() {
    _generation++;
    _lifecycleListener?.dispose();

    final runtime = _runtime;
    _runtime = null;
    _commands = null;

    if (runtime != null &&
        widget._effectiveLifecyclePolicy.closeOnWidgetDispose) {
      unawaited(_closeRuntime(runtime, widget._closeConfiguration));
    }

    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _configureLifecycleListener();
    unawaited(_start(configuration: widget._closeConfiguration));
  }

  void _configureLifecycleListener() {
    _lifecycleListener?.dispose();

    final policy = widget._effectiveLifecyclePolicy;
    _lifecycleListener = policy.closeOnApplicationExit
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
    ++_generation;
    final runtime = _runtime;

    if (mounted) {
      setState(() {
        _runtime = null;
        _commands = null;
        _error = null;
        _stackTrace = null;
      });
    } else {
      _runtime = null;
      _commands = null;
    }

    if (runtime == null) {
      return Future<void>.value();
    }

    return _closeRuntime(runtime, widget._closeConfiguration);
  }

  Future<Stopwatch?> _prepareLoading(int generation) async {
    if (widget.loadingBuilder == null) {
      return null;
    }

    // Wait until Flutter has presented the loading state at least once.
    await WidgetsBinding.instance.endOfFrame;

    if (!mounted || generation != _generation) {
      return null;
    }

    return Stopwatch()..start();
  }

  Future<void> _restart({
    required _BetterEffectCloseConfiguration previousConfiguration,
  }) async {
    final generation = ++_generation;
    final previous = _runtime;

    if (mounted) {
      setState(() {
        _runtime = null;
        _commands = null;
        _error = null;
        _stackTrace = null;
      });
    }

    if (previous != null) {
      await _closeRuntime(previous, previousConfiguration);
    }

    if (!mounted || generation != _generation) {
      return;
    }

    await _start(
      generation: generation,
      configuration: widget._closeConfiguration,
    );
  }

  void _retry() {
    unawaited(_restart(previousConfiguration: widget._closeConfiguration));
  }

  Future<void> _start({
    int? generation,
    required _BetterEffectCloseConfiguration configuration,
  }) async {
    final currentGeneration = generation ?? ++_generation;
    final module = widget.module;
    final backendFactory = widget.backendFactory;
    final observer = widget.observer;

    final loadingStopwatch = await _prepareLoading(currentGeneration);

    if (!mounted || currentGeneration != _generation) {
      return;
    }

    try {
      final runtime = await module.start(backend: backendFactory?.call());

      await _waitMinimumLoadingDuration(loadingStopwatch);

      if (!mounted || currentGeneration != _generation) {
        await _closeRuntime(runtime, configuration);
        return;
      }

      setState(() {
        _runtime = runtime;
        _commands = EffectCommands(runtime, observer: observer);
        _error = null;
        _stackTrace = null;
      });
    } catch (error, stackTrace) {
      await _waitMinimumLoadingDuration(loadingStopwatch);

      if (!mounted || currentGeneration != _generation) {
        return;
      }

      setState(() {
        _runtime = null;
        _commands = null;
        _error = error;
        _stackTrace = stackTrace;
      });
    }
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

  Future<void> _waitMinimumLoadingDuration(Stopwatch? stopwatch) async {
    if (stopwatch == null) {
      return;
    }

    final minimum = widget.minimumLoadingDuration;

    if (minimum == Duration.zero) {
      return;
    }

    final remaining = minimum - stopwatch.elapsed;

    if (remaining.isNegative || remaining == Duration.zero) {
      return;
    }

    await Future<void>.delayed(remaining);
  }
}
