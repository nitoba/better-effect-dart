part of '../../better_effect.dart';

/// Execution-scoped Module operations for a long-lived [Runtime].
///
/// Each call creates a fresh child resolver, installs [Module] into the current
/// execution Scope, and resolves local services before falling back to the root
/// Runtime. The execution Module never mutates the root environment.
extension RuntimeExecutionModuleOps on Runtime {
  /// Start a managed execution with temporary providers and resources.
  ///
  /// The returned handle has the same logical-versus-physical ownership
  /// semantics as [Runtime.execute]. Local resources remain alive until physical
  /// completion, including after timeout or interruption.
  EffectExecution<A, E> executeWith<A extends Object, E extends Object>(
    Module module,
    Effect<A, E> effect, {
    String? label,
  }) {
    return execute(_withExecutionModule(module, effect), label: label);
  }

  /// Run an Effect with a temporary Module and return its typed Result.
  Future<ResultDart<A, E>> runWith<A extends Object, E extends Object>(
    Module module,
    Effect<A, E> effect, {
    String? executionLabel,
  }) async {
    final exit = await runExitWith(
      module,
      effect,
      executionLabel: executionLabel,
    );
    return _resultFromExit(exit);
  }

  /// Run an Effect with a temporary Module while preserving every [Exit].
  Future<Exit<A, E>> runExitWith<A extends Object, E extends Object>(
    Module module,
    Effect<A, E> effect, {
    String? executionLabel,
  }) {
    return executeWith(module, effect, label: executionLabel).exit;
  }
}

Effect<A, E> _withExecutionModule<A extends Object, E extends Object>(
  Module module,
  Effect<A, E> effect,
) {
  return Effect<A, E>._((rootContext) async {
    rootContext.cancellation.throwIfCancelled();

    final overlay = _createExecutionOverlay(rootContext.backend);
    await _ownExecutionOverlay(rootContext.scope, overlay);

    final overlayContext = _RuntimeContext(
      backend: overlay,
      scope: rootContext.scope,
      cancellation: rootContext.cancellation,
      overrides: rootContext.overrides,
      locals: rootContext.locals,
      observation: rootContext.observation,
      cleanupFailureReporter: rootContext.cleanupFailureReporter,
    );

    await _installExecutionModule(module, overlayContext);

    // Module startup is a cooperative boundary. If interruption arrived while a
    // resource was being acquired, the user Effect does not start afterwards.
    rootContext.cancellation.throwIfCancelled();

    return effect._run(overlayContext);
  }, effect._localBindings);
}

ResolverBackend _createExecutionOverlay(ResolverBackend root) {
  if (root is! ResolverBackendOverlayFactory) {
    throw ResolverBackendOverlayUnsupportedException(root.runtimeType);
  }

  final factory = root as ResolverBackendOverlayFactory;
  final overlay = factory.createExecutionOverlay();
  if (identical(root, overlay)) {
    throw StateError(
      '${root.runtimeType}.createExecutionOverlay() returned the root backend. '
      'Execution overlays must be isolated and independently closeable.',
    );
  }

  return overlay;
}

Future<void> _ownExecutionOverlay(Scope scope, ResolverBackend overlay) async {
  try {
    // Registered before Module resources, so Scope LIFO closes Effect resources,
    // then Module resources, then constructor-backed overlay services.
    scope.addFinalizer((_) => overlay.close());
  } catch (error, stackTrace) {
    try {
      await Future<void>.sync(overlay.close);
    } catch (closeError, closeStackTrace) {
      Error.throwWithStackTrace(
        CompositeDefect(
          primary: error,
          primaryStackTrace: stackTrace,
          secondary: closeError,
          secondaryStackTrace: closeStackTrace,
        ),
        stackTrace,
      );
    }

    Error.throwWithStackTrace(error, stackTrace);
  }
}

Future<void> _installExecutionModule(
  Module module,
  _RuntimeContext context,
) async {
  for (final binding in module) {
    if (!binding._isResource) {
      binding._register(context.backend);
    }
  }

  context.backend.commit();

  for (final binding in module) {
    if (binding._isResource) {
      await binding._startResource(context);
    }
  }

  await Future<void>.sync(context.backend.activate);
}
