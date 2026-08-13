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

  /// Replace matching bindings while preserving the rest of this module.
  Module overrideWith(Iterable<Binding> overrides) {
    final replacementBindings = List<Binding>.unmodifiable(overrides);
    _validateBindings(replacementBindings);

    final identities = replacementBindings
        .map((binding) => binding._identity)
        .toSet();

    return Module([
      for (final binding in _bindings)
        if (!identities.contains(binding._identity)) binding,
      ...replacementBindings,
    ]);
  }

  /// Run an Effect, return its typed Result, and close the runtime afterwards.
  Future<ResultDart<A, E>> run<A extends Object, E extends Object>(
    Effect<A, E> effect, {
    ResolverBackend? backend,
  }) async {
    final exit = await runExit(effect, backend: backend);
    return _resultFromExit(exit);
  }

  /// Run an Effect, preserve defects in [Exit], and close the runtime afterwards.
  Future<Exit<A, E>> runExit<A extends Object, E extends Object>(
    Effect<A, E> effect, {
    ResolverBackend? backend,
  }) async {
    Runtime? runtime;

    try {
      runtime = await start(backend: backend);
      final exit = await runtime.runExit(effect);

      try {
        await runtime._closeWith(exit);
        return exit;
      } catch (error, stackTrace) {
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

        return ExitDefect<A, E>(error, stackTrace);
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
  Future<Runtime> start({ResolverBackend? backend}) {
    return Runtime.start(this, backend: backend);
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
