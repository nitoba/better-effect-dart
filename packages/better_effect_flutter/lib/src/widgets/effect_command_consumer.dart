part of '../../better_effect_flutter.dart';

/// Combines one-shot command side effects with state-driven UI rendering.
final class EffectCommandConsumer<A extends Object, E extends Object>
    extends StatelessWidget {
  const EffectCommandConsumer({
    required this.command,
    required this.builder,
    this.child,
    this.buildWhen,
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
  final EffectCommandWidgetBuilder<A, E> builder;
  final Widget? child;
  final EffectCommandBuildWhen<A, E>? buildWhen;
  final EffectCommandListenWhen<A, E>? listenWhen;
  final EffectCommandChanged<A, E>? onChanged;
  final EffectCommandIdleListener<A>? onIdle;
  final EffectCommandRunningListener<A>? onRunning;
  final EffectCommandSuccessListener<A>? onSuccess;
  final EffectCommandFailureListener<A, E>? onFailure;
  final EffectCommandDefectListener<A>? onDefect;
  final EffectCommandInterruptedListener<A>? onInterrupted;
  final bool fireImmediately;

  @override
  Widget build(BuildContext context) {
    return EffectCommandListener<A, E>(
      command: command,
      listenWhen: listenWhen,
      onChanged: onChanged,
      onIdle: onIdle,
      onRunning: onRunning,
      onSuccess: onSuccess,
      onFailure: onFailure,
      onDefect: onDefect,
      onInterrupted: onInterrupted,
      fireImmediately: fireImmediately,
      child: EffectCommandBuilder<A, E>(
        command: command,
        builder: builder,
        buildWhen: buildWhen,
        child: child,
      ),
    );
  }
}
