part of '../../better_effect.dart';

/// Backend contract used by [Runtime] to register and resolve services.
///
/// Applications normally use [AutoInjectorBackend], the default implementation.
/// A custom backend can be supplied to [Module.start] or [Module.run].
abstract interface class ResolverBackend {
  /// Register a constructor-backed service.
  void register<T extends Object>(
    Function constructor, {
    required Lifetime lifetime,
    String? key,
  });

  /// Register an already-created service instance.
  void registerInstance<T extends Object>(T instance, {String? key});

  /// Finish the registration phase so services can be resolved.
  void commit();

  /// Eagerly initialize bindings declared with [Lifetime.singleton].
  ///
  /// This is called after module resources have been acquired, allowing eager
  /// services to depend on those resources.
  FutureOr<void> activate();

  /// Resolve a service by type or by an optional backend key.
  T resolve<T extends Object>({String? key});

  /// Release all backend-owned state.
  FutureOr<void> close();
}

/// Optional backend capability used by [RuntimeExecutionModuleOps].
///
/// An execution overlay owns an isolated registration set that resolves its
/// local services first and falls back to the backend that created it. Closing
/// the overlay must release only overlay-owned state; it must never close or
/// mutate the parent backend.
///
/// Custom backends that do not implement this capability can still power normal
/// Runtime execution, but `runWith`, `runExitWith`, and `executeWith` complete
/// with [ResolverBackendOverlayUnsupportedException].
abstract interface class ResolverBackendOverlayFactory {
  /// Create one isolated, local-first child backend.
  ResolverBackend createExecutionOverlay();
}
