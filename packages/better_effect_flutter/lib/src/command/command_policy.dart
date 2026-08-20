part of '../../better_effect_flutter.dart';

/// Execution coordination used by a [CommandPolicy].
enum CommandPolicyKind {
  /// Reuse the authoritative in-flight caller and start no duplicate work.
  drop,

  /// Start every accepted invocation while only the newest owns visible state.
  latest,

  /// Serialize accepted invocations in FIFO order.
  queue,
}

/// Behavior when a bounded Command queue has no remaining capacity.
enum QueueOverflow {
  /// Refuse the newest invocation and complete its caller with
  /// [ExitInterrupted].
  rejectNewest,

  /// Discard the newest invocation and complete its caller with
  /// [ExitInterrupted].
  ///
  /// This has the same caller outcome as [rejectNewest], but is reported as a
  /// drop through [EffectCommandPolicyEvent].
  dropNewest,

  /// Interrupt the oldest queued caller and admit the newest invocation.
  dropOldest,
}

/// Timing stage applied before execution coordination.
enum TriggerPolicyKind { immediate, debounce, throttle }

/// Immutable timing policy for typed-input Commands.
///
/// Debounce and throttle are intentionally unavailable for zero-input Commands.
/// Their duration is driven by the contextual [EffectClock] service.
final class TriggerPolicy {
  const TriggerPolicy.immediate()
    : kind = TriggerPolicyKind.immediate,
      duration = Duration.zero,
      leading = true,
      trailing = false;

  /// Wait for a quiet [duration] before executing the latest input.
  ///
  /// With [leading] enabled, the first invocation starts immediately. With
  /// [trailing] enabled, the latest invocation received during the window runs
  /// after the quiet period. At least one edge must be enabled.
  const TriggerPolicy.debounce(
    this.duration, {
    this.leading = false,
    this.trailing = true,
  }) : kind = TriggerPolicyKind.debounce;

  /// Allow at most one leading execution per [duration].
  ///
  /// When [trailing] is enabled, the latest invocation received during the
  /// active window runs when that window closes. A trailing execution opens the
  /// next throttle window immediately. At least one edge must be enabled.
  const TriggerPolicy.throttle(
    this.duration, {
    this.leading = true,
    this.trailing = false,
  }) : kind = TriggerPolicyKind.throttle;

  final TriggerPolicyKind kind;
  final Duration duration;
  final bool leading;
  final bool trailing;

  bool get isImmediate => kind == TriggerPolicyKind.immediate;

  void _validate({required bool acceptsInput}) {
    if (duration.isNegative) {
      throw ArgumentError.value(
        duration,
        'trigger.duration',
        'must not be negative',
      );
    }
    if (!isImmediate && !acceptsInput) {
      throw ArgumentError(
        '${kind.name} triggers require an EffectCommand with typed input.',
      );
    }
    if (!isImmediate && !leading && !trailing) {
      throw ArgumentError(
        '${kind.name} must enable its leading edge, trailing edge, or both.',
      );
    }
  }

  @override
  String toString() {
    if (isImmediate) return 'TriggerPolicy.immediate()';
    return 'TriggerPolicy.${kind.name}($duration, leading: $leading, '
        'trailing: $trailing)';
  }
}

/// Immutable execution and timing policy for an Effect Command.
///
/// The timing stage runs before [kind]. This keeps debounce/throttle composable
/// with drop, latest, and queue without introducing separate Command classes.
final class CommandPolicy {
  const CommandPolicy.drop({this.trigger = const TriggerPolicy.immediate()})
    : kind = CommandPolicyKind.drop,
      cancelPrevious = false,
      maxPending = null,
      overflow = QueueOverflow.rejectNewest;

  const CommandPolicy.latest({
    this.cancelPrevious = false,
    this.trigger = const TriggerPolicy.immediate(),
  }) : kind = CommandPolicyKind.latest,
       maxPending = null,
       overflow = QueueOverflow.rejectNewest;

  const CommandPolicy.queue({
    this.maxPending,
    this.overflow = QueueOverflow.rejectNewest,
    this.trigger = const TriggerPolicy.immediate(),
  }) : kind = CommandPolicyKind.queue,
       cancelPrevious = false;

  final CommandPolicyKind kind;

  /// Interrupt the previous authoritative managed execution when a newer latest
  /// invocation is accepted.
  final bool cancelPrevious;

  /// Maximum callers waiting behind the active queue execution.
  ///
  /// Null means unbounded and zero means no waiting caller is admitted.
  final int? maxPending;

  final QueueOverflow overflow;
  final TriggerPolicy trigger;

  void _validate({required bool acceptsInput}) {
    trigger._validate(acceptsInput: acceptsInput);
    final maximum = maxPending;
    if (maximum != null && maximum < 0) {
      throw ArgumentError.value(
        maximum,
        'policy.maxPending',
        'must be null or non-negative',
      );
    }
  }

  EffectCommandConcurrency get _legacyConcurrency => switch (kind) {
    CommandPolicyKind.drop => EffectCommandConcurrency.drop,
    CommandPolicyKind.latest => EffectCommandConcurrency.latest,
    CommandPolicyKind.queue => EffectCommandConcurrency.queue,
  };

  @override
  String toString() {
    return switch (kind) {
      CommandPolicyKind.drop => 'CommandPolicy.drop(trigger: $trigger)',
      CommandPolicyKind.latest =>
        'CommandPolicy.latest(cancelPrevious: $cancelPrevious, '
            'trigger: $trigger)',
      CommandPolicyKind.queue =>
        'CommandPolicy.queue(maxPending: $maxPending, overflow: $overflow, '
            'trigger: $trigger)',
    };
  }
}

/// A policy decision that does not need a new Command state or domain failure.
enum CommandPolicyDecision {
  started,
  coalesced,
  queued,
  triggerScheduled,
  triggerFired,
  replaced,
  rejected,
  dropped,
  interruptedPrevious,
  cancelled,
  defect,
}

/// Machine-readable reason attached to [EffectCommandPolicyEvent].
enum CommandPolicyReason {
  activeDrop,
  latestSuperseded,
  queueRejectedNewest,
  queueDroppedNewest,
  queueDroppedOldest,
  debounceReplaced,
  debounceSuppressed,
  throttleReplaced,
  throttleSuppressed,
  commandCancelled,
  commandDisposed,
  triggerClockUnavailable,
  triggerClockFailed,
}

/// Observes policy decisions from one or more Commands.
typedef EffectCommandPolicyObserver =
    void Function(EffectCommandPolicyEvent event);

/// Immutable diagnostic event for Command policy decisions.
///
/// Inputs and Effect values are deliberately omitted so instrumentation cannot
/// accidentally expose user data. [invocationId] identifies the caller request;
/// [executionId] is present only after a real Effect execution starts.
final class EffectCommandPolicyEvent {
  const EffectCommandPolicyEvent({
    required this.policy,
    required this.decision,
    required this.timestamp,
    required this.invocationId,
    required this.executionId,
    required this.pendingCount,
    required this.queuedCount,
    required this.reason,
    required this.debugLabel,
  });

  final CommandPolicy policy;
  final CommandPolicyDecision decision;
  final DateTime timestamp;
  final int invocationId;
  final int? executionId;
  final int pendingCount;
  final int queuedCount;
  final CommandPolicyReason? reason;
  final String? debugLabel;

  @override
  String toString() {
    final label = debugLabel == null ? '' : '[$debugLabel] ';
    final suffix = reason == null ? '' : ' (${reason!.name})';
    return '$label${decision.name}$suffix invocation=$invocationId '
        'execution=$executionId pending=$pendingCount queued=$queuedCount';
  }
}
