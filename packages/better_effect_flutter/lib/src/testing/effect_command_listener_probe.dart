import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:flutter/widgets.dart';

/// Records states delivered by [EffectCommandListener.onChanged].
///
/// Pass [call] directly to the listener and assert that each revision was
/// delivered only once:
///
/// ```dart
/// final probe = EffectCommandListenerProbe<User, UserFailure>();
/// EffectCommandListener(
///   command: command,
///   onChanged: probe.call,
///   child: const Screen(),
/// );
/// ```
final class EffectCommandListenerProbe<A extends Object, E extends Object> {
  final List<EffectCommandState<A, E>> _deliveries =
      <EffectCommandState<A, E>>[];

  List<EffectCommandState<A, E>> get deliveries {
    return List<EffectCommandState<A, E>>.unmodifiable(_deliveries);
  }

  Iterable<S> deliveriesOf<S extends EffectCommandState<A, E>>() {
    return _deliveries.whereType<S>();
  }

  void call(BuildContext context, EffectCommandState<A, E> state) {
    _deliveries.add(state);
  }

  void clear() => _deliveries.clear();

  /// Verify that no visible revision was delivered more than once.
  void expectUniqueRevisions() {
    final seen = <int>{};
    final duplicates = <int>[];
    for (final state in _deliveries) {
      if (!seen.add(state.revision)) duplicates.add(state.revision);
    }
    if (duplicates.isEmpty) return;

    throw DuplicateEffectCommandListenerDeliveryException(duplicates);
  }
}

final class DuplicateEffectCommandListenerDeliveryException
    implements Exception {
  DuplicateEffectCommandListenerDeliveryException(Iterable<int> revisions)
    : revisions = List<int>.unmodifiable(revisions);

  final List<int> revisions;

  @override
  String toString() {
    return 'EffectCommandListener delivered revisions more than once: '
        '$revisions.';
  }
}
