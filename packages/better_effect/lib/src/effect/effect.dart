part of '../../better_effect.dart';

/// A lazy Effect body with access to contextual services and typed failures.
typedef EffectBody<A extends Object, E extends Object> =
    FutureOr<A> Function(EffectContext<E> use);

typedef _EffectRunner<A extends Object, E extends Object> =
    Future<ResultDart<A, E>> Function(_RuntimeContext context);

/// A lazy computation that can succeed with [A] or fail with [E].
///
/// Dependencies are requested from the [EffectContext] at the point where they
/// are used:
///
/// ```dart
/// Effect<User, AppFailure> findUser(String id) => .result((use) async {
///   final database = use<Database>();
///
///   return use.unwrap(database.findUser(id));
/// });
/// ```
final class Effect<A extends Object, E extends Object> {
  const Effect._(
    this._runner, [
    this._localBindings = const <EffectLocalBinding>[],
  ]);

  final _EffectRunner<A, E> _runner;

  /// Statically visible top-level bindings used for execution start/end
  /// metadata. The actual local values remain applied by the Effect wrappers.
  final List<EffectLocalBinding> _localBindings;

  Map<String, Object> _initialObserverMetadata() {
    return _effectLocalBindingMetadata(_localBindings);
  }

  /// Build an Effect using ordinary `async`/`await` syntax.
  ///
  /// Calls to [EffectContext.unwrap], [EffectContext.result], and
  /// [EffectContext.fail] short-circuit this body and propagate their typed
  /// failure.
  factory Effect.result(EffectBody<A, E> body) {
    return Effect<A, E>._((context) async {
      try {
        final value = await Future<A>.sync(
          () => body(_EffectContext<E>(context)),
        );

        return Success<A, E>(value);
      } on _Raised<E> catch (raised) {
        return Failure<A, E>(raised.error);
      }
    });
  }

  /// Create an Effect that succeeds with an existing value.
  factory Effect.succeed(A value) {
    return Effect<A, E>._((_) async => Success<A, E>(value));
  }

  /// Create an Effect that fails with an expected error.
  factory Effect.fail(E error) {
    return Effect<A, E>._((_) async => Failure<A, E>(error));
  }

  /// Lazily evaluate a synchronous computation.
  ///
  /// Exceptions remain defects. Use [Effect.tryAsync] to map exceptions into
  /// typed failures.
  factory Effect.sync(A Function() operation) {
    return Effect<A, E>._((_) async {
      final value = await Future<A>.sync(operation);
      return Success<A, E>(value);
    });
  }

  /// Lazily convert a Result-producing operation into an Effect.
  factory Effect.fromResult(FutureOr<ResultDart<A, E>> Function() operation) {
    return Effect<A, E>._((_) async => operation());
  }

  /// Lazily create an Effect from another Effect-producing function.
  factory Effect.defer(Effect<A, E> Function() operation) {
    return Effect<A, E>._((context) => operation()._run(context));
  }

  /// Convert exceptions raised by a sync or async operation into typed errors.
  ///
  /// Only objects implementing [Exception] are caught. Dart [Error] values and
  /// other thrown objects remain defects.
  factory Effect.tryAsync(
    FutureOr<A> Function() operation, {
    required E Function(Exception error, StackTrace stackTrace) onError,
  }) {
    return Effect<A, E>._((_) async {
      try {
        final value = await Future<A>.sync(operation);
        return Success<A, E>(value);
      } on Exception catch (error, stackTrace) {
        return Failure<A, E>(onError(error, stackTrace));
      }
    });
  }

  /// Convert every thrown object, including Dart [Error] values, into a typed
  /// failure. Prefer [Effect.tryAsync] unless this broader behavior is intended.
  factory Effect.tryAll(
    FutureOr<A> Function() operation, {
    required E Function(Object error, StackTrace stackTrace) onError,
  }) {
    return Effect<A, E>._((_) async {
      try {
        final value = await Future<A>.sync(operation);
        return Success<A, E>(value);
      } catch (error, stackTrace) {
        return Failure<A, E>(onError(error, stackTrace));
      }
    });
  }

  /// Describe the resolution of a service as an infallible Effect.
  static Effect<T, Never> service<T extends Object>([ServiceKey<T>? key]) {
    return Effect<T, Never>.result((use) => use<T>(key));
  }

  /// Compose two Effects sequentially and return a Dart record.
  static Effect<(X, Y), F> zip<
    X extends Object,
    Y extends Object,
    F extends Object
  >(Effect<X, F> first, Effect<Y, F> second) {
    return Effect<(X, Y), F>.result((use) async {
      final left = await use.unwrap(first);
      final right = await use.unwrap(second);
      return (left, right);
    });
  }

  /// Start two Effects concurrently and return both successful values.
  ///
  /// Dart Futures do not provide fiber-style cancellation. If one side fails,
  /// the other side is still awaited before the result is returned.
  static Effect<(X, Y), F> parZip<
    X extends Object,
    Y extends Object,
    F extends Object
  >(Effect<X, F> first, Effect<Y, F> second) {
    return Effect<(X, Y), F>._((context) async {
      final completed = await Future.wait<Object>(<Future<Object>>[
        first._run(context).then<Object>((result) => result),
        second._run(context).then<Object>((result) => result),
      ]);

      final leftResult = completed[0] as ResultDart<X, F>;
      final rightResult = completed[1] as ResultDart<Y, F>;

      return leftResult.fold<ResultDart<(X, Y), F>>(
        (left) => rightResult.fold<ResultDart<(X, Y), F>>(
          (right) => Success<(X, Y), F>((left, right)),
          (error) => Failure<(X, Y), F>(error),
        ),
        (error) => Failure<(X, Y), F>(error),
      );
    });
  }

  Future<ResultDart<A, E>> _run(_RuntimeContext context) {
    return _runner(context);
  }
}
