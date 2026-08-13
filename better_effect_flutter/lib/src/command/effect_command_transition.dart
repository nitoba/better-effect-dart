part of '../../better_effect_flutter.dart';

/// Observes transitions from every command created by one [EffectCommands]
/// instance.
typedef EffectCommandObserver =
    void Function(EffectCommandTransition transition);

/// One state transition produced by an Effect command.
///
/// The state values are intentionally exposed as [Object] because one global
/// observer can receive transitions from commands with different generic types.
final class EffectCommandTransition {
  const EffectCommandTransition({
    required this.previous,
    required this.current,
    required this.timestamp,
    this.debugLabel,
  });

  final String? debugLabel;

  final Object previous;

  final Object current;

  final DateTime timestamp;

  @override
  String toString() {
    final label = debugLabel == null ? '' : '[$debugLabel] ';
    return '$label$previous -> $current';
  }
}
