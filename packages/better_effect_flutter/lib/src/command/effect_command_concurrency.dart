part of '../../better_effect_flutter.dart';

/// Compatibility shorthand for the three original Command coordination modes.
///
/// New code can use [CommandPolicy] so timing, cancellation, queue bounds, and
/// overflow behavior can be configured without multiplying enum values.
enum EffectCommandConcurrency {
  /// Return the active Future and do not start duplicate work.
  drop,

  /// Start every execution, but only let the latest one update UI state.
  latest,

  /// Serialize executions in request order.
  queue,
}

/// Translate the compatibility enum into its exact immutable policy.
extension EffectCommandConcurrencyPolicy on EffectCommandConcurrency {
  CommandPolicy get asPolicy => switch (this) {
    EffectCommandConcurrency.drop => const CommandPolicy.drop(),
    EffectCommandConcurrency.latest => const CommandPolicy.latest(),
    EffectCommandConcurrency.queue => const CommandPolicy.queue(),
  };
}
