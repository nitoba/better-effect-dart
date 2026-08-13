part of '../../better_effect.dart';

/// The capabilities available inside [Effect.result].
///
/// The context is deliberately read-only: code can resolve services, compose
/// Results and Effects, fail with a typed error, read Effect locals, and acquire
/// scoped resources. It cannot mutate the Module or the DI backend.
abstract interface class EffectContext<E extends Object> {
  /// Resolve a dependency at the point where the code uses it.
  T call<T extends Object>([ServiceKey<T>? key]);

  /// Named equivalent of [call] for autocomplete and discoverability.
  T service<T extends Object>([ServiceKey<T>? key]);

  /// Run another Effect in the same environment and propagate its failure.
  Future<A> unwrap<A extends Object, F extends E>(Effect<A, F> effect);

  /// Unwrap a synchronous or asynchronous Result and propagate its failure.
  Future<A> result<A extends Object, F extends E>(
    FutureOr<ResultDart<A, F>> source,
  );

  /// Convert a synchronous or asynchronous operation that throws [Exception]
  /// into a typed failure.
  Future<A> tryAsync<A extends Object, F extends E>(
    FutureOr<A> Function() operation, {
    required F Function(Exception error, StackTrace stackTrace) onError,
  });

  /// Stop the current Effect with an expected, typed failure.
  Never fail<F extends E>(F error);

  /// Read the current value of an [EffectLocal].
  T local<T extends Object>(EffectLocal<T> local);

  /// Acquire a resource and register its release callback in the current scope.
  Future<R> acquire<R extends Object, F extends E>(
    Effect<R, F> acquisition, {
    required FutureOr<void> Function(R resource) release,
  });
}

final class _Raised<E extends Object> {
  const _Raised(this.error);

  final E error;
}

final class _EffectContext<E extends Object> implements EffectContext<E> {
  const _EffectContext(this._runtime);

  final _RuntimeContext _runtime;

  @override
  T call<T extends Object>([ServiceKey<T>? key]) {
    return _runtime._resolve<T>(key);
  }

  @override
  T service<T extends Object>([ServiceKey<T>? key]) {
    return _runtime._resolve<T>(key);
  }

  @override
  Future<A> unwrap<A extends Object, F extends E>(Effect<A, F> effect) async {
    final result = await effect._run(_runtime);

    return result.fold<A>((value) => value, (error) => throw _Raised<E>(error));
  }

  @override
  Future<A> result<A extends Object, F extends E>(
    FutureOr<ResultDart<A, F>> source,
  ) async {
    final result = await source;

    return result.fold<A>((value) => value, (error) => throw _Raised<E>(error));
  }

  @override
  Future<A> tryAsync<A extends Object, F extends E>(
    FutureOr<A> Function() operation, {
    required F Function(Exception error, StackTrace stackTrace) onError,
  }) async {
    try {
      return await Future<A>.sync(operation);
    } on Exception catch (error, stackTrace) {
      throw _Raised<E>(onError(error, stackTrace));
    }
  }

  @override
  Never fail<F extends E>(F error) {
    throw _Raised<E>(error);
  }

  @override
  T local<T extends Object>(EffectLocal<T> local) {
    return _runtime._local(local);
  }

  @override
  Future<R> acquire<R extends Object, F extends E>(
    Effect<R, F> acquisition, {
    required FutureOr<void> Function(R resource) release,
  }) async {
    final resource = await unwrap(acquisition);

    _runtime.scope._addFinalizer((_) => release(resource));

    return resource;
  }
}
