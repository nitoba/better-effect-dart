part of '../../better_effect.dart';

/// Executes Effects against the environment built from a [Module].
final class Runtime {
  Runtime._(this._rootContext);

  final _RuntimeContext _rootContext;
  bool _closed = false;

  /// Build a runtime, install constructor bindings, and acquire resources.
  static Future<Runtime> start(
    Module module, {
    ResolverBackend? backend,
  }) async {
    final resolver = backend ?? AutoInjectorBackend();
    final rootScope = Scope._();
    final context = _RuntimeContext(
      backend: resolver,
      scope: rootScope,
      overrides: const <_ServiceIdentity, Object>{},
      locals: const <Object, Object>{},
    );

    try {
      for (final binding in module) {
        if (!binding._isResource) {
          binding._register(resolver);
        }
      }

      resolver.commit();

      for (final binding in module) {
        if (binding._isResource) {
          await binding._startResource(context);
        }
      }

      await Future<void>.sync(resolver.activate);

      return Runtime._(context);
    } catch (error, stackTrace) {
      Object? cleanupError;
      StackTrace? cleanupStackTrace;

      try {
        await rootScope._close(ExitDefect<Object, Object>(error, stackTrace));
      } catch (releaseError, releaseStack) {
        cleanupError = releaseError;
        cleanupStackTrace = releaseStack;
      }

      try {
        await Future<void>.sync(resolver.close);
      } catch (backendError, backendStackTrace) {
        if (cleanupError == null) {
          cleanupError = backendError;
          cleanupStackTrace = backendStackTrace;
        } else {
          cleanupError = CompositeDefect(
            primary: cleanupError,
            primaryStackTrace: cleanupStackTrace!,
            secondary: backendError,
            secondaryStackTrace: backendStackTrace,
          );
          cleanupStackTrace = backendStackTrace;
        }
      }

      if (cleanupError != null) {
        Error.throwWithStackTrace(
          CompositeDefect(
            primary: error,
            primaryStackTrace: stackTrace,
            secondary: cleanupError,
            secondaryStackTrace: cleanupStackTrace!,
          ),
          stackTrace,
        );
      }

      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Read-only access to the runtime's services at application boundaries.
  Services get services {
    _ensureOpen();
    return Services._(_rootContext);
  }

  bool get isClosed => _closed;

  /// Run an Effect and convert unexpected defects back into thrown errors.
  Future<ResultDart<A, E>> run<A extends Object, E extends Object>(
    Effect<A, E> effect,
  ) async {
    final exit = await runExit(effect);
    return _resultFromExit(exit);
  }

  /// Run an Effect while preserving success, failure, and defects in [Exit].
  Future<Exit<A, E>> runExit<A extends Object, E extends Object>(
    Effect<A, E> effect,
  ) async {
    _ensureOpen();

    final executionScope = Scope._();
    final context = _rootContext._withScope(executionScope);

    Exit<A, E> exit;

    try {
      final result = await effect._run(context);
      exit = result.fold<Exit<A, E>>(
        (value) => ExitSuccess<A, E>(value),
        (error) => ExitFailure<A, E>(error),
      );
    } catch (error, stackTrace) {
      exit = ExitDefect<A, E>(error, stackTrace);
    }

    try {
      await executionScope._close(exit);
      return exit;
    } catch (releaseError, releaseStackTrace) {
      if (exit is ExitDefect<A, E>) {
        return ExitDefect<A, E>(
          CompositeDefect(
            primary: exit.defect,
            primaryStackTrace: exit.stackTrace,
            secondary: releaseError,
            secondaryStackTrace: releaseStackTrace,
          ),
          exit.stackTrace,
        );
      }

      return ExitDefect<A, E>(releaseError, releaseStackTrace);
    }
  }

  /// Close this runtime and release module-owned resources.
  Future<void> close() {
    return _closeWith(const ExitInterrupted<Object, Object>());
  }

  Future<void> _closeWith(Exit<Object, Object> exit) async {
    if (_closed) {
      return;
    }

    _closed = true;

    Object? scopeError;
    StackTrace? scopeStackTrace;

    try {
      await _rootContext.scope._close(exit);
    } catch (error, stackTrace) {
      scopeError = error;
      scopeStackTrace = stackTrace;
    }

    Object? backendError;
    StackTrace? backendStackTrace;

    try {
      await Future<void>.sync(_rootContext.backend.close);
    } catch (error, stackTrace) {
      backendError = error;
      backendStackTrace = stackTrace;
    }

    if (scopeError != null && backendError != null) {
      Error.throwWithStackTrace(
        CompositeDefect(
          primary: scopeError,
          primaryStackTrace: scopeStackTrace!,
          secondary: backendError,
          secondaryStackTrace: backendStackTrace!,
        ),
        scopeStackTrace,
      );
    }

    if (scopeError != null) {
      Error.throwWithStackTrace(scopeError, scopeStackTrace!);
    }

    if (backendError != null) {
      Error.throwWithStackTrace(backendError, backendStackTrace!);
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw const RuntimeClosedException();
    }
  }
}
