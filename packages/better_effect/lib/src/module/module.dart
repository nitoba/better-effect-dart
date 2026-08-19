part of '../../better_effect.dart';

/// A composable collection of service bindings.
///
/// Modules are descriptions. Constructors and resources are not evaluated until
/// [start], [run], or [runExit] is called.
final class Module extends IterableBase<Binding> {
  final List<Binding> _bindings;

  Module(Iterable<Binding> bindings)
    : _bindings = List<Binding>.unmodifiable(bindings) {
    _validateBindings(_bindings);
  }

  /// Create a module by concatenating other modules in declaration order.
  factory Module.merge(Iterable<Module> modules) {
    return Module([for (final module in modules) ...module]);
  }

  /// The immutable bindings declared by this module.
  List<Binding> get bindings => _bindings;

  @override
  Iterator<Binding> get iterator => _bindings.iterator;

  /// Replace matching bindings without changing their declaration positions.
  ///
  /// Override identities that do not exist in this Module are appended in the
  /// order they are declared. Preserving existing positions keeps resource
  /// acquisition and reverse release order stable.
  Module overrideWith(Iterable<Binding> overrides) {
    final replacementBindings = List<Binding>.unmodifiable(overrides);
    _validateBindings(replacementBindings);

    final replacements = <_BindingIdentity, Binding>{
      for (final binding in replacementBindings) binding._identity: binding,
    };
    final existingIdentities = _bindings
        .map((binding) => binding._identity)
        .toSet();

    return Module([
      for (final binding in _bindings)
        replacements[binding._identity] ?? binding,
      for (final replacement in replacementBindings)
        if (!existingIdentities.contains(replacement._identity)) replacement,
    ]);
  }

  /// Run an Effect, return its typed Result, and close the runtime afterwards.
  Future<ResultDart<A, E>> run<A extends Object, E extends Object>(
    Effect<A, E> effect, {
    ResolverBackend? backend,
    CleanupFailureObserver? cleanupFailureObserver,
    String? executionLabel,
  }) async {
    final exit = await runExit(
      effect,
      backend: backend,
      cleanupFailureObserver: cleanupFailureObserver,
      executionLabel: executionLabel,
    );
    return _resultFromExit(exit);
  }

  /// Run an Effect, preserve defects in [Exit], and close the runtime afterwards.
  Future<Exit<A, E>> runExit<A extends Object, E extends Object>(
    Effect<A, E> effect, {
    ResolverBackend? backend,
    CleanupFailureObserver? cleanupFailureObserver,
    String? executionLabel,
  }) async {
    Runtime? runtime;

    try {
      runtime = await start(
        backend: backend,
        cleanupFailureObserver: cleanupFailureObserver,
      );
      final exit = await runtime.runExit(
        effect,
        executionLabel: executionLabel,
      );

      try {
        await runtime._closeWith(exit);
        return exit;
      } catch (error, stackTrace) {
        if (exit is ExitSuccess<A, E>) {
          return ExitDefect<A, E>(error, stackTrace);
        }

        if (exit is ExitDefect<A, E>) {
          return ExitDefect<A, E>(
            CompositeDefect(
              primary: exit.defect,
              primaryStackTrace: exit.stackTrace,
              secondary: error,
              secondaryStackTrace: stackTrace,
            ),
            exit.stackTrace,
          );
        }

        return exit;
      }
    } catch (error, stackTrace) {
      if (runtime != null) {
        try {
          await runtime.close();
        } catch (_) {
          // Runtime cleanup is already represented by the start/run defect.
        }
      }

      return ExitDefect<A, E>(error, stackTrace);
    }
  }

  /// Start a long-lived runtime from this module.
  Future<Runtime> start({
    ResolverBackend? backend,
    CleanupFailureObserver? cleanupFailureObserver,
  }) {
    return Runtime.start(
      this,
      backend: backend,
      cleanupFailureObserver: cleanupFailureObserver,
    );
  }

  static void _validateBindings(Iterable<Binding> bindings) {
    final identities = <_BindingIdentity>{};

    for (final binding in bindings) {
      if (!identities.add(binding._identity)) {
        throw DuplicateServiceBindingException(
          serviceType: binding.serviceType,
          key: binding._identity.backendKey,
        );
      }
    }
  }
}
