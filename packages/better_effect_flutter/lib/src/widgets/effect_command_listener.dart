part of '../../better_effect_flutter.dart';

typedef EffectCommandChanged<A extends Object, E extends Object> =
    void Function(BuildContext context, EffectCommandState<A, E> state);

typedef EffectCommandDefectListener<A extends Object> =
    void Function(
      BuildContext context,
      Object defect,
      StackTrace stackTrace,
      A? previous,
    );

typedef EffectCommandFailureListener<A extends Object, E extends Object> =
    void Function(BuildContext context, E error, A? previous);

typedef EffectCommandIdleListener<A extends Object> =
    void Function(BuildContext context, A? previous);

typedef EffectCommandInterruptedListener<A extends Object> =
    void Function(BuildContext context, A? previous);

/// Decides whether a transition should be delivered to a listener.
typedef EffectCommandListenWhen<A extends Object, E extends Object> =
    bool Function(
      EffectCommandState<A, E> previous,
      EffectCommandState<A, E> current,
    );

typedef EffectCommandRunningListener<A extends Object> =
    void Function(BuildContext context, A? previous);

typedef EffectCommandSuccessListener<A extends Object> =
    void Function(BuildContext context, A value);

/// Delivers command transitions as one-shot Flutter presentation effects.
///
/// Each state revision is consumed once. Navigation, SnackBars, dialogs, and
/// analytics therefore do not require `clearError()` or `clearResult()` calls.
final class EffectCommandListener<A extends Object, E extends Object>
    extends StatefulWidget {
  const EffectCommandListener({
    required this.command,
    required this.child,
    this.listenWhen,
    this.onChanged,
    this.onIdle,
    this.onRunning,
    this.onSuccess,
    this.onFailure,
    this.onDefect,
    this.onInterrupted,
    this.fireImmediately = false,
    super.key,
  });

  final ValueListenable<EffectCommandState<A, E>> command;
  final Widget child;
  final EffectCommandListenWhen<A, E>? listenWhen;
  final EffectCommandChanged<A, E>? onChanged;
  final EffectCommandIdleListener<A>? onIdle;
  final EffectCommandRunningListener<A>? onRunning;
  final EffectCommandSuccessListener<A>? onSuccess;
  final EffectCommandFailureListener<A, E>? onFailure;
  final EffectCommandDefectListener<A>? onDefect;
  final EffectCommandInterruptedListener<A>? onInterrupted;

  /// Whether the state present when this listener mounts should be emitted.
  final bool fireImmediately;

  @override
  State<EffectCommandListener<A, E>> createState() =>
      _EffectCommandListenerState<A, E>();
}

final class _EffectCommandListenerState<A extends Object, E extends Object>
    extends State<EffectCommandListener<A, E>> {
  late EffectCommandState<A, E> _current;
  int _commandGeneration = 0;

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void didUpdateWidget(EffectCommandListener<A, E> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (identical(oldWidget.command, widget.command)) {
      return;
    }

    oldWidget.command.removeListener(_handleChange);
    _commandGeneration++;
    _current = widget.command.value;
    widget.command.addListener(_handleChange);

    if (widget.fireImmediately) {
      _scheduleDispatch(_current);
    }
  }

  @override
  void dispose() {
    _commandGeneration++;
    widget.command.removeListener(_handleChange);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _current = widget.command.value;
    widget.command.addListener(_handleChange);

    if (widget.fireImmediately) {
      _scheduleDispatch(_current);
    }
  }

  void _handleChange() {
    final previous = _current;
    final current = widget.command.value;

    if (previous.revision == current.revision) {
      return;
    }

    _current = current;

    if (!(widget.listenWhen?.call(previous, current) ?? true)) {
      return;
    }

    _scheduleDispatch(current);
  }

  void _scheduleDispatch(EffectCommandState<A, E> state) {
    final generation = _commandGeneration;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _commandGeneration) {
        return;
      }

      widget.onChanged?.call(context, state);

      switch (state) {
        case EffectCommandIdle<A, E>(:final previous):
          widget.onIdle?.call(context, previous);

        case EffectCommandRunning<A, E>(:final previous):
          widget.onRunning?.call(context, previous);

        case EffectCommandSuccess<A, E>(:final value):
          widget.onSuccess?.call(context, value);

        case EffectCommandFailure<A, E>(:final error, :final previous):
          widget.onFailure?.call(context, error, previous);

        case EffectCommandDefect<A, E>(
          :final defect,
          :final stackTrace,
          :final previous,
        ):
          widget.onDefect?.call(context, defect, stackTrace, previous);

        case EffectCommandInterrupted<A, E>(:final previous):
          widget.onInterrupted?.call(context, previous);
      }
    });
  }
}
