import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:flutter/widgets.dart';

/// Minimal widget-test boundary for an externally owned Runtime.
///
/// The test remains responsible for closing [runtime]. The helper adds
/// [Directionality] so small widget fixtures do not need a complete MaterialApp
/// unless the UI under test requires one.
final class BetterEffectTestApp extends StatelessWidget {
  const BetterEffectTestApp({
    required this.runtime,
    required this.child,
    this.commandObserver,
    this.policyObserver,
    this.textDirection = TextDirection.ltr,
    super.key,
  });

  final Runtime runtime;
  final Widget child;
  final EffectCommandObserver? commandObserver;
  final EffectCommandPolicyObserver? policyObserver;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: textDirection,
      child: BetterEffectProvider.value(
        runtime: runtime,
        observer: commandObserver,
        policyObserver: policyObserver,
        child: child,
      ),
    );
  }
}
