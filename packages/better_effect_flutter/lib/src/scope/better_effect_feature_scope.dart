part of '../../better_effect_flutter.dart';

/// Builds a feature subtree after its child [Runtime] has started.
typedef BetterEffectFeatureBuilder = Widget Function(BuildContext context);

/// Builds the startup-error state for a feature child [Runtime].
typedef BetterEffectFeatureErrorBuilder =
    Widget Function(
      BuildContext context,
      Object error,
      StackTrace stackTrace,
      VoidCallback retry,
    );

/// Owns one child [Runtime] for a Flutter feature subtree.
///
/// The feature environment resolves its own Module first and falls back to the
/// nearest parent Runtime. It stays alive across multiple ViewModels and
/// Commands, then closes when this widget leaves the tree or intentionally
/// restarts.
final class BetterEffectFeatureScope extends StatefulWidget {
  const BetterEffectFeatureScope({
    required this.module,
    required this.builder,
    this.label,
    this.restartKey,
    this.loadingBuilder,
    this.errorBuilder,
    this.observer,
    this.policyObserver,
    this.gracePeriod = Duration.zero,
    this.interruptExecutionsBeforeClose = true,
    this.onRuntimeCloseError,
    super.key,
  });

  /// Providers and resources owned by the feature Runtime.
  final Module module;

  /// Builds the subtree after the feature Runtime is available.
  final BetterEffectFeatureBuilder builder;

  /// Optional label propagated to Runtime observability events.
  final String? label;

  /// Changing this value intentionally replaces the feature Runtime.
  final Object? restartKey;

  /// UI shown while the child Runtime starts or restarts.
  final WidgetBuilder? loadingBuilder;

  /// UI shown when child Runtime startup fails.
  final BetterEffectFeatureErrorBuilder? errorBuilder;

  /// Observer inherited by Commands created inside this feature.
  final EffectCommandObserver? observer;

  /// Policy observer inherited by Commands created inside this feature.
  final EffectCommandPolicyObserver? policyObserver;

  /// Time to drain active child work before cooperative interruption.
  final Duration gracePeriod;

  /// Whether child shutdown requests cooperative interruption after the grace
  /// period.
  final bool interruptExecutionsBeforeClose;

  /// Optional handler for failures raised while closing an owned child Runtime.
  final void Function(Object error, StackTrace stackTrace)? onRuntimeCloseError;

  _BetterEffectCloseConfiguration get _closeConfiguration {
    return _BetterEffectCloseConfiguration(
      policy: BetterEffectLifecyclePolicy.widget(
        interruptExecutionsBeforeClose: interruptExecutionsBeforeClose,
        gracePeriod: gracePeriod,
      ),
      onError: onRuntimeCloseError,
      ownerDescription: 'a BetterEffectFeatureScope child Runtime',
    );
  }

  @override
  State<BetterEffectFeatureScope> createState() =>
      _BetterEffectFeatureScopeState();
}

final class _BetterEffectFeatureScopeState
    extends State<BetterEffectFeatureScope> {
  final Map<Runtime, Future<void>> _closeOperations = <Runtime, Future<void>>{};

  Runtime? _parentRuntime;
  Runtime? _runtime;
  EffectCommands? _commands;
  Object? _error;
  StackTrace? _stackTrace;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parent = BetterEffectScope.of(context).runtime;
    if (identical(parent, _parentRuntime)) return;

    _parentRuntime = parent;
    unawaited(_restart(parent, widget._closeConfiguration));
  }

  @override
  void didUpdateWidget(BetterEffectFeatureScope oldWidget) {
    super.didUpdateWidget(oldWidget);

    final shouldRestart =
        !identical(oldWidget.module, widget.module) ||
        oldWidget.restartKey != widget.restartKey ||
        oldWidget.label != widget.label;
    if (shouldRestart) {
      final parent = _parentRuntime;
      if (parent != null) {
        unawaited(_restart(parent, oldWidget._closeConfiguration));
      }
      return;
    }

    final observersChanged =
        !identical(oldWidget.observer, widget.observer) ||
        !identical(oldWidget.policyObserver, widget.policyObserver);
    if (observersChanged && _runtime != null && mounted) {
      setState(() {
        _commands = EffectCommands(
          _runtime!,
          observer: widget.observer,
          policyObserver: widget.policyObserver,
        );
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    final runtime = _runtime;
    _runtime = null;
    _commands = null;
    if (runtime != null) {
      unawaited(_closeRuntime(runtime, widget._closeConfiguration));
    }
    super.dispose();
  }

  void _retry() {
    final parent = _parentRuntime;
    if (parent != null) {
      unawaited(_restart(parent, widget._closeConfiguration));
    }
  }

  Future<void> _restart(
    Runtime parent,
    _BetterEffectCloseConfiguration previousConfiguration,
  ) async {
    final generation = ++_generation;

    // Keep lifecycle callbacks synchronous and publish UI changes after the
    // current Flutter lifecycle callback returns.
    await Future<void>.value();
    if (!mounted ||
        generation != _generation ||
        !identical(parent, _parentRuntime)) {
      return;
    }

    final previous = _runtime;
    setState(() {
      _runtime = null;
      _commands = null;
      _error = null;
      _stackTrace = null;
    });

    if (previous != null) {
      await _closeRuntime(previous, previousConfiguration);
    }

    if (!mounted ||
        generation != _generation ||
        !identical(parent, _parentRuntime)) {
      return;
    }

    try {
      final runtime = await parent.fork(widget.module, label: widget.label);

      if (!mounted ||
          generation != _generation ||
          !identical(parent, _parentRuntime)) {
        await _closeRuntime(runtime, widget._closeConfiguration);
        return;
      }

      setState(() {
        _runtime = runtime;
        _commands = EffectCommands(
          runtime,
          observer: widget.observer,
          policyObserver: widget.policyObserver,
        );
        _error = null;
        _stackTrace = null;
      });
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
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
    final existing = _closeOperations[runtime];
    if (existing != null) return existing;

    final operation = configuration.close(runtime);
    _closeOperations[runtime] = operation;
    unawaited(
      operation.then<void>((_) {
        _closeOperations.remove(runtime);
      }),
    );
    return operation;
  }
}
