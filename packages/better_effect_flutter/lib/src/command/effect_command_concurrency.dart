part of '../../better_effect_flutter.dart';

/// Defines how a command reacts when another execution is requested while work
/// is already in flight.
enum EffectCommandConcurrency {
  /// Return the active Future and do not start duplicate work.
  ///
  /// This is the safest default for submit buttons, refresh actions, and
  /// destructive operations triggered by repeated taps.
  drop,

  /// Start every execution, but only let the latest one update UI state.
  ///
  /// Older Dart Futures are not cancelled. Their callers still receive their
  /// outcomes, while stale completions cannot replace newer command state.
  latest,

  /// Serialize executions in request order.
  ///
  /// Useful for local writes, ordered uploads, and toggles whose user intent
  /// must be preserved.
  queue,
}
