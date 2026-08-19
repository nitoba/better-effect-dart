part of '../../better_effect.dart';

/// Controls how a constructor-backed service is instantiated.
enum Lifetime {
  /// A new instance is created on every resolution.
  factory,

  /// The instance is created while the runtime starts.
  singleton,

  /// The instance is created on its first resolution and then reused.
  lazySingleton,
}
