part of '../../better_effect_flutter.dart';

/// Read-only state and coordination metadata for one Command.
///
/// [state] remains the authoritative presentation state. Counts are
/// published separately so selectors can observe queues and trigger
/// windows without creating artificial state revisions or consuming
/// one-shot listener events.
final class EffectCommandSnapshot<A extends Object, E extends Object> {
  const EffectCommandSnapshot({
    required this.state,
    required this.lastExit,
    required this.pendingCount,
    required this.queuedCount,
    required this.triggerPendingCount,
    required this.policy,
  });

  final EffectCommandState<A, E> state;
  final Exit<A, E>? lastExit;
  final int pendingCount;
  final int queuedCount;
  final int triggerPendingCount;
  final CommandPolicy policy;

  int get revision => state.revision;
  bool get isRunning => state.isRunning;
  A? get dataOrNull => state.dataOrNull;
  E? get errorOrNull => state.errorOrNull;

  bool get isTerminal => switch (state) {
    EffectCommandIdle<A, E>() || EffectCommandRunning<A, E>() => false,
    _ => true,
  };

  @override
  String toString() {
    return 'EffectCommandSnapshot(state: $state, '
        'pendingCount: $pendingCount, queuedCount: $queuedCount, '
        'triggerPendingCount: $triggerPendingCount, '
        'lastExit: $lastExit)';
  }
}

final class _EffectCommandSnapshotNotifier<A extends Object, E extends Object>
    extends ChangeNotifier
    implements ValueListenable<EffectCommandSnapshot<A, E>> {
  _EffectCommandSnapshotNotifier(this._value);

  EffectCommandSnapshot<A, E> _value;

  @override
  EffectCommandSnapshot<A, E> get value => _value;

  void update(EffectCommandSnapshot<A, E> next) {
    final current = _value;
    if (identical(current.state, next.state) &&
        identical(current.lastExit, next.lastExit) &&
        current.pendingCount == next.pendingCount &&
        current.queuedCount == next.queuedCount &&
        current.triggerPendingCount == next.triggerPendingCount &&
        identical(current.policy, next.policy)) {
      return;
    }

    _value = next;
    notifyListeners();
  }
}
