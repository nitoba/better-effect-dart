part of '../../better_effect.dart';

final class _ServiceIdentity {
  const _ServiceIdentity(this.type, this.key);

  final Type type;
  final String? key;

  @override
  bool operator ==(Object other) {
    return other is _ServiceIdentity && other.type == type && other.key == key;
  }

  @override
  int get hashCode => Object.hash(type, key);
}

final class _RuntimeContext {
  const _RuntimeContext({
    required this.backend,
    required this.scope,
    required this.overrides,
    required this.locals,
  });

  final ResolverBackend backend;
  final Scope scope;
  final Map<_ServiceIdentity, Object> overrides;
  final Map<Object, Object> locals;

  T _resolve<T extends Object>([ServiceKey<T>? key]) {
    final identity = _ServiceIdentity(T, key?._backendKey);

    if (overrides.containsKey(identity)) {
      return overrides[identity]! as T;
    }

    return backend.resolve<T>(key: key?._backendKey);
  }

  T _local<T extends Object>(EffectLocal<T> local) {
    if (locals.containsKey(local)) {
      return locals[local]! as T;
    }

    return local.initial;
  }

  _RuntimeContext _withScope(Scope childScope) {
    return _RuntimeContext(
      backend: backend,
      scope: childScope,
      overrides: overrides,
      locals: locals,
    );
  }

  _RuntimeContext _withOverride<T extends Object>(
    T instance, {
    ServiceKey<T>? key,
  }) {
    final identity = _ServiceIdentity(T, key?._backendKey);

    return _RuntimeContext(
      backend: backend,
      scope: scope,
      overrides: <_ServiceIdentity, Object>{...overrides, identity: instance},
      locals: locals,
    );
  }

  _RuntimeContext _withLocal<T extends Object>(EffectLocal<T> local, T value) {
    return _RuntimeContext(
      backend: backend,
      scope: scope,
      overrides: overrides,
      locals: <Object, Object>{...locals, local: value},
    );
  }
}
