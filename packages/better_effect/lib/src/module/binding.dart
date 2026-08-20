part of '../../better_effect.dart';

/// Creates a resource using services already available in the module.
typedef ResourceAcquire<T extends Object> =
    FutureOr<T> Function(Services services);

final class _BindingIdentity {
  const _BindingIdentity(this.serviceType, this.backendKey);

  final Type serviceType;
  final String? backendKey;

  @override
  bool operator ==(Object other) {
    return other is _BindingIdentity &&
        other.serviceType == serviceType &&
        other.backendKey == backendKey;
  }

  @override
  int get hashCode => Object.hash(serviceType, backendKey);
}

/// A declarative service registration used inside a [Module].
///
/// The expected list type enables Dart's dot shorthand syntax:
///
/// ```dart
/// final appModule = Module([
///   .provide<Database>(DatabaseLive.new),
///   .provide<UserRepository>(UserRepositoryLive.new),
/// ]);
/// ```
sealed class Binding {
  const Binding._();

  /// Register a constructor-backed service.
  ///
  /// The default lifetime is [Lifetime.lazySingleton].
  static Binding provide<T extends Object>(
    Function constructor, {
    Lifetime lifetime = Lifetime.lazySingleton,
    ServiceKey<T>? key,
  }) {
    return _ConstructorBinding<T>(
      constructor: constructor,
      lifetime: lifetime,
      key: key,
    );
  }

  /// Register a service that is recreated on every resolution.
  static Binding factory<T extends Object>(
    Function constructor, {
    ServiceKey<T>? key,
  }) {
    return _ConstructorBinding<T>(
      constructor: constructor,
      lifetime: Lifetime.factory,
      key: key,
    );
  }

  /// Register a service created eagerly when the runtime starts.
  static Binding singleton<T extends Object>(
    Function constructor, {
    ServiceKey<T>? key,
  }) {
    return _ConstructorBinding<T>(
      constructor: constructor,
      lifetime: Lifetime.singleton,
      key: key,
    );
  }

  /// Register a service created on first use and reused afterwards.
  static Binding lazySingleton<T extends Object>(
    Function constructor, {
    ServiceKey<T>? key,
  }) {
    return _ConstructorBinding<T>(
      constructor: constructor,
      lifetime: Lifetime.lazySingleton,
      key: key,
    );
  }

  /// Register an already-created service instance.
  static Binding instance<T extends Object>(T value, {ServiceKey<T>? key}) {
    return _InstanceBinding<T>(value: value, key: key);
  }

  /// Register an asynchronously acquired, runtime-owned resource.
  ///
  /// Resources are acquired in module declaration order and released in reverse
  /// order when the Runtime closes. The release callback receives the outcome
  /// that closed the Runtime Scope.
  static Binding resource<T extends Object>({
    required ResourceAcquire<T> acquire,
    required ResourceRelease<T> release,
    ServiceKey<T>? key,
  }) {
    return _ResourceBinding<T>(acquire: acquire, release: release, key: key);
  }

  Type get serviceType;

  _BindingIdentity get _identity;

  bool get _isResource => false;

  void _register(ResolverBackend backend);

  Future<void> _startResource(_RuntimeContext context) async {}
}

final class _ConstructorBinding<T extends Object> extends Binding {
  const _ConstructorBinding({
    required this.constructor,
    required this.lifetime,
    required this.key,
  }) : super._();

  final Function constructor;
  final Lifetime lifetime;
  final ServiceKey<T>? key;

  @override
  Type get serviceType => T;

  @override
  _BindingIdentity get _identity {
    return _BindingIdentity(T, key?._backendKey);
  }

  @override
  void _register(ResolverBackend backend) {
    backend.register<T>(constructor, lifetime: lifetime, key: key?._backendKey);
  }
}

final class _InstanceBinding<T extends Object> extends Binding {
  const _InstanceBinding({required this.value, required this.key}) : super._();

  final T value;
  final ServiceKey<T>? key;

  @override
  Type get serviceType => T;

  @override
  _BindingIdentity get _identity {
    return _BindingIdentity(T, key?._backendKey);
  }

  @override
  void _register(ResolverBackend backend) {
    backend.registerInstance<T>(value, key: key?._backendKey);
  }
}

final class _ResourceBinding<T extends Object> extends Binding {
  const _ResourceBinding({
    required this.acquire,
    required this.release,
    required this.key,
  }) : super._();

  final ResourceAcquire<T> acquire;
  final ResourceRelease<T> release;
  final ServiceKey<T>? key;

  @override
  Type get serviceType => T;

  @override
  _BindingIdentity get _identity {
    return _BindingIdentity(T, key?._backendKey);
  }

  @override
  bool get _isResource => true;

  @override
  void _register(ResolverBackend backend) {}

  @override
  Future<void> _startResource(_RuntimeContext context) async {
    late T value;

    try {
      value = await context._acquireResource<T>(
        operation: () => Future<T>.sync(() => acquire(Services._(context))),
        release: release,
        serviceType: T,
        serviceKey: key?.name,
        source: ResourceAcquisitionSource.module,
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ResourceAcquisitionException(
          serviceType: T,
          key: key?.name,
          cause: error,
          causeStackTrace: stackTrace,
        ),
        stackTrace,
      );
    }

    context.backend.registerInstance<T>(value, key: key?._backendKey);
  }
}
