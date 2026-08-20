part of '../../better_effect.dart';

/// Transformations available on every [Effect].
extension EffectTransformOps<A extends Object, E extends Object>
    on Effect<A, E> {
  /// Transform the successful value.
  Effect<B, E> map<B extends Object>(B Function(A value) transform) {
    return Effect<B, E>._((context) async {
      final result = await _run(context);
      return result.map<B>(transform);
    }, _localBindings);
  }

  /// Sequence another Effect that uses this Effect's successful value.
  Effect<B, E> flatMap<B extends Object>(Effect<B, E> Function(A value) next) {
    return Effect<B, E>._((context) async {
      final result = await _run(context);

      return result.fold<Future<ResultDart<B, E>>>(
        (value) => next(value)._run(context),
        (error) async => Failure<B, E>(error),
      );
    }, _localBindings);
  }

  /// Transform the typed failure.
  Effect<A, F> mapError<F extends Object>(F Function(E error) transform) {
    return Effect<A, F>._((context) async {
      final result = await _run(context);
      return result.mapError<F>(transform);
    }, _localBindings);
  }

  /// Recover from every typed failure with another Effect.
  Effect<A, F> catchAll<F extends Object>(
    Effect<A, F> Function(E error) recover,
  ) {
    return Effect<A, F>._((context) async {
      final result = await _run(context);

      return result.fold<Future<ResultDart<A, F>>>(
        (value) async => Success<A, F>(value),
        (error) => recover(error)._run(context),
      );
    }, _localBindings);
  }

  /// Run an observation after success without changing the value.
  Effect<A, E> tap(FutureOr<void> Function(A value) inspect) {
    return Effect<A, E>._((context) async {
      final result = await _run(context);

      return result.fold<Future<ResultDart<A, E>>>((value) async {
        await inspect(value);
        return Success<A, E>(value);
      }, (error) async => Failure<A, E>(error));
    }, _localBindings);
  }

  /// Run an observation after a typed failure without changing the failure.
  Effect<A, E> tapError(FutureOr<void> Function(E error) inspect) {
    return Effect<A, E>._((context) async {
      final result = await _run(context);

      return result.fold<Future<ResultDart<A, E>>>(
        (value) async => Success<A, E>(value),
        (error) async {
          await inspect(error);
          return Failure<A, E>(error);
        },
      );
    }, _localBindings);
  }

  /// Discard the success value while preserving the typed failure.
  Effect<Unit, E> asUnit() {
    return map<Unit>((_) => unit);
  }

  /// Run this Effect with a local service override.
  Effect<A, E> provide<T extends Object>(T instance, {ServiceKey<T>? key}) {
    return Effect<A, E>._((context) {
      return _run(context._withOverride<T>(instance, key: key));
    }, _localBindings);
  }

  /// Run this Effect with a locally overridden [EffectLocal] value.
  Effect<A, E> withLocal<T extends Object>(EffectLocal<T> local, T value) {
    return withLocals(<EffectLocalBinding>[local.bind(value)]);
  }

  /// Apply a heterogeneous batch of typed [EffectLocal] values.
  ///
  /// ```dart
  /// program.withLocals([
  ///   requestId.bind('req-123'),
  ///   traceId.bind('trace-456'),
  /// ]);
  /// ```
  ///
  /// Bindings later in this iterable replace earlier bindings for the same
  /// local. Existing inner `withLocal`/`withLocals` wrappers remain closer to the
  /// original Effect and therefore keep their existing nesting precedence.
  Effect<A, E> withLocals(Iterable<EffectLocalBinding> bindings) {
    final values = List<EffectLocalBinding>.unmodifiable(bindings);
    if (values.isEmpty) {
      return this;
    }

    return Effect<A, E>._(
      (context) => _run(context._withLocals(values)),
      List<EffectLocalBinding>.unmodifiable(<EffectLocalBinding>[
        ...values,
        ..._localBindings,
      ]),
    );
  }

  /// Fail with [onTimeout] when this Effect does not finish in time.
  ///
  /// The underlying Future is not cancelled because Dart Futures do not expose
  /// general cancellation. The Runtime keeps the execution Scope alive until
  /// the original Future completes.
  Effect<A, E> timeout(Duration duration, {required E Function() onTimeout}) {
    return Effect<A, E>._((context) {
      final source = _run(context);

      return source.timeout(
        duration,
        onTimeout: () {
          context._trackPhysical(source.then<void>((_) {}));
          return Failure<A, E>(onTimeout());
        },
      );
    }, _localBindings);
  }

  /// Turn the typed failure channel into a successful Result value.
  Effect<ResultDart<A, E>, Never> either() {
    return Effect<ResultDart<A, E>, Never>._((context) async {
      final result = await _run(context);
      return Success<ResultDart<A, E>, Never>(result);
    }, _localBindings);
  }
}

/// Convert a synchronous Result into a lazy Effect value.
extension ResultDartEffectInterop<A extends Object, E extends Object>
    on ResultDart<A, E> {
  Effect<A, E> toEffect() {
    return Effect<A, E>.fromResult(() => this);
  }
}

/// Convert an asynchronous Result into an Effect.
extension AsyncResultDartEffectInterop<A extends Object, E extends Object>
    on AsyncResultDart<A, E> {
  Effect<A, E> toEffect() {
    return Effect<A, E>.fromResult(() => this);
  }
}
