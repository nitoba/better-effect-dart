import 'package:better_effect_flutter/better_effect_flutter.dart';

/// Records [EffectCommandPolicyEvent] values in delivery order.
///
/// Pass [call] to `EffectCommands(policyObserver: ...)`, a provider/bootstrap
/// policy observer, or one Command's `policyObserver` argument.
final class EffectCommandPolicyProbe {
  final List<EffectCommandPolicyEvent> _events = <EffectCommandPolicyEvent>[];

  List<EffectCommandPolicyEvent> get events {
    return List<EffectCommandPolicyEvent>.unmodifiable(_events);
  }

  void call(EffectCommandPolicyEvent event) => _events.add(event);

  Iterable<EffectCommandPolicyEvent> whereDecision(
    CommandPolicyDecision decision,
  ) {
    return _events.where((event) => event.decision == decision);
  }

  EffectCommandPolicyEvent? lastWhereDecision(CommandPolicyDecision decision) {
    for (var index = _events.length - 1; index >= 0; index--) {
      final event = _events[index];
      if (event.decision == decision) return event;
    }
    return null;
  }

  void clear() => _events.clear();

  /// Verify the exact policy-decision sequence without depending on a matcher
  /// library.
  void expectDecisions(Iterable<CommandPolicyDecision> expected) {
    final expectedValues = List<CommandPolicyDecision>.of(expected);
    final actual = <CommandPolicyDecision>[
      for (final event in _events) event.decision,
    ];

    if (actual.length == expectedValues.length) {
      var matches = true;
      for (var index = 0; index < actual.length; index++) {
        if (actual[index] != expectedValues[index]) {
          matches = false;
          break;
        }
      }
      if (matches) return;
    }

    throw EffectCommandPolicyProbeExpectationException(
      expected: expectedValues,
      actual: actual,
    );
  }
}

final class EffectCommandPolicyProbeExpectationException implements Exception {
  const EffectCommandPolicyProbeExpectationException({
    required this.expected,
    required this.actual,
  });

  final List<CommandPolicyDecision> expected;
  final List<CommandPolicyDecision> actual;

  @override
  String toString() {
    return 'Expected Command policy decisions $expected, but recorded $actual.';
  }
}
