part of '../../better_effect.dart';

/// A runtime-local value inherited by nested Effects.
///
/// Effect locals are useful for request IDs, tracing metadata, feature flags,
/// authentication context, and other values that should vary per execution
/// without relying on global state or Zones.
final class EffectLocal<T extends Object> {
  const EffectLocal(this.initial, {this.name});

  final T initial;
  final String? name;

  @override
  String toString() => name == null ? 'EffectLocal<$T>' : 'EffectLocal($name)';
}
