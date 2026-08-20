part of '../../better_effect.dart';

abstract interface class _EffectLocalDescriptor {
  String? get _metadataKey;
}

/// A runtime-local value inherited by nested Effects.
///
/// Effect locals are useful for request IDs, tracing metadata, feature flags,
/// authentication context, and other values that should vary per execution
/// without relying on global state or Zones.
final class EffectLocal<T extends Object> implements _EffectLocalDescriptor {
  /// Create a normal local value that is not projected to observer metadata.
  const EffectLocal(this.initial, {String? name})
    : _name = name,
      _metadataKey = null;

  /// Create a local whose current value is included in Runtime observer events.
  ///
  /// Use immutable, diagnostic-safe values such as strings, numbers, booleans,
  /// IDs, or immutable records. Observer maps are immutable snapshots, but the
  /// Runtime does not clone arbitrary user objects.
  const EffectLocal.metadata(this.initial, {required String name})
    : _name = name,
      _metadataKey = name,
      assert(name != '');

  final T initial;
  final String? _name;

  /// Optional diagnostic name for this local.
  String? get name => _name;

  @override
  final String? _metadataKey;

  /// Bind a value for use with [EffectTransformOps.withLocals].
  EffectLocalBinding bind(T value) => _EffectLocalBinding<T>(this, value);

  @override
  String toString() => name == null ? 'EffectLocal<$T>' : 'EffectLocal($name)';
}

/// A heterogeneous, type-safe local binding.
///
/// Values can be collected in one list because [EffectLocal.bind] validates the
/// value against its local's generic type before erasing that type here.
sealed class EffectLocalBinding {
  const EffectLocalBinding();

  void _writeLocal(Map<Object, Object> target);

  void _writeMetadata(Map<String, Object> target);
}

final class _EffectLocalBinding<T extends Object> extends EffectLocalBinding {
  const _EffectLocalBinding(this.local, this.value);

  final EffectLocal<T> local;
  final T value;

  @override
  void _writeLocal(Map<Object, Object> target) {
    target[local] = value;
  }

  @override
  void _writeMetadata(Map<String, Object> target) {
    final key = local._metadataKey;
    if (key != null) {
      target[key] = value;
    }
  }
}

Map<String, Object> _effectLocalBindingMetadata(
  Iterable<EffectLocalBinding> bindings,
) {
  final metadata = <String, Object>{};
  for (final binding in bindings) {
    binding._writeMetadata(metadata);
  }
  return metadata;
}

Map<String, Object> _effectLocalMetadata(Map<Object, Object> locals) {
  final metadata = <String, Object>{};

  for (final entry in locals.entries) {
    final local = entry.key;
    if (local is! _EffectLocalDescriptor) {
      continue;
    }

    final key = local._metadataKey;
    if (key != null) {
      metadata[key] = entry.value;
    }
  }

  return metadata;
}
