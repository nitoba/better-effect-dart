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

/// Declaratively starts a [Module] inside an existing Flutter application.
///
/// Prefer [runBetterEffectApp] when better_effect owns the application root.
/// Use this widget for add-to-app scenarios, tests, previews, or feature roots
/// that need an asynchronous application Runtime.
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
    this.closeRuntimeOnDetach = true,
    this.onRuntimeCloseError,
    super.key,
  });

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

  final bool closeRuntimeOnDetach;

  final void Function(Object error, StackTrace stackTrace)? onRuntimeCloseError;

  @override
  State<BetterEffectBootstrap> createState() => _BetterEffectBootstrapState();
}

final class _BetterEffectBootstrapState extends State<BetterEffectBootstrap> {
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

    final shouldRestart =
        !identical(oldWidget.module, widget.module) ||
        oldWidget.restartKey != widget.restartKey;

    if (oldWidget.closeRuntimeOnDetach != widget.closeRuntimeOnDetach) {
      _configureLifecycleListener();
    }

    if (shouldRestart) {
      unawaited(_restart());
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
    if (runtime != null) {
      unawaited(_closeRuntime(runtime));
    }

    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    _configureLifecycleListener();

    if (widget.loadingBuilder == null) {
      unawaited(_start());
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      unawaited(_start());
    });
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
            'while closing a BetterEffectBootstrap Runtime',
          ),
        ),
      );
    }
  }

  void _configureLifecycleListener() {
    _lifecycleListener?.dispose();
    _lifecycleListener = widget.closeRuntimeOnDetach
        ? AppLifecycleListener(
            onDetach: () {
              final runtime = _runtime;
              if (runtime != null) {
                unawaited(_closeRuntime(runtime));
              }
            },
          )
        : null;
  }

  Future<Stopwatch?> _prepareLoading(int generation) async {
    if (widget.loadingBuilder == null) {
      return null;
    }

    // Espera o Flutter realmente apresentar
    // o estado de loading.
    await WidgetsBinding.instance.endOfFrame;

    if (!mounted || generation != _generation) {
      return null;
    }

    return Stopwatch()..start();
  }

  Future<void> _restart() async {
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
      await _closeRuntime(previous);
    }

    if (!mounted || generation != _generation) {
      return;
    }

    await _start(generation: generation);
  }

  void _retry() {
    unawaited(_restart());
  }

  Future<void> _start({int? generation}) async {
    final currentGeneration = generation ?? ++_generation;

    final loadingStopwatch = await _prepareLoading(currentGeneration);

    if (!mounted || currentGeneration != _generation) {
      return;
    }

    try {
      final runtime = await widget.module.start(
        backend: widget.backendFactory?.call(),
      );

      await _waitMinimumLoadingDuration(loadingStopwatch);

      if (!mounted || currentGeneration != _generation) {
        await _closeRuntime(runtime);
        return;
      }

      setState(() {
        _runtime = runtime;

        _commands = EffectCommands(runtime, observer: widget.observer);

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
