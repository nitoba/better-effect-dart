part of '../../better_effect.dart';

/// The default [ResolverBackend], powered by `package:auto_injector`.
final class AutoInjectorBackend
    implements ResolverBackend, ResolverBackendOverlayFactory {
  factory AutoInjectorBackend([AutoInjector? injector]) {
    final root = injector ?? AutoInjector();
    return AutoInjectorBackend._(
      injector: root,
      commitInjector: root,
      disposeRecursively: true,
    );
  }

  AutoInjectorBackend._({
    required AutoInjector injector,
    required AutoInjector commitInjector,
    required bool disposeRecursively,
  }) : _injector = injector,
       _commitInjector = commitInjector,
       _disposeRecursively = disposeRecursively;

  factory AutoInjectorBackend._executionOverlay(AutoInjector parent) {
    final local = AutoInjector();
    final shell = AutoInjector();

    // The shell is owned by this overlay. It can see the long-lived parent as a
    // downward child, while the local injector resolves upward through the shell.
    // This gives local-first constructor injection without adding short-lived
    // children to the long-lived parent injector.
    shell.addInjector(parent);
    shell.addInjector(local, resolveUpward: true);

    return AutoInjectorBackend._(
      injector: local,
      commitInjector: shell,
      disposeRecursively: false,
    );
  }

  final AutoInjector _injector;
  final AutoInjector _commitInjector;
  final bool _disposeRecursively;
  final List<void Function()> _eagerInitializers = <void Function()>[];

  bool _committed = false;
  bool _activated = false;
  bool _closed = false;

  @override
  Future<void> activate() async {
    _ensureOpen();

    if (_activated) {
      return;
    }

    if (!_committed) {
      commit();
    }

    for (final initialize in _eagerInitializers) {
      initialize();
    }

    _activated = true;
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }

    _closed = true;
    _committed = false;
    _activated = false;
    _eagerInitializers.clear();

    Object? closeError;
    StackTrace? closeStackTrace;

    void capture(Object error, StackTrace stackTrace) {
      if (closeError == null) {
        closeError = error;
        closeStackTrace = stackTrace;
        return;
      }

      closeError = CompositeDefect(
        primary: closeError!,
        primaryStackTrace: closeStackTrace!,
        secondary: error,
        secondaryStackTrace: stackTrace,
      );
    }

    if (_disposeRecursively) {
      try {
        _injector.disposeRecursive();
      } catch (error, stackTrace) {
        capture(error, stackTrace);
      }
    } else {
      // Local instances are disposed first. Disposing the shell afterwards
      // removes the temporary graph/listeners without traversing into the root.
      try {
        _injector.dispose();
      } catch (error, stackTrace) {
        capture(error, stackTrace);
      }

      try {
        _commitInjector.dispose();
      } catch (error, stackTrace) {
        capture(error, stackTrace);
      }
    }

    final error = closeError;
    if (error != null) {
      Error.throwWithStackTrace(error, closeStackTrace!);
    }
  }

  @override
  void commit() {
    _ensureOpen();

    if (_committed) {
      return;
    }

    _commitInjector.commit();
    _committed = true;
  }

  @override
  ResolverBackend createExecutionOverlay() {
    _ensureOpen();
    return AutoInjectorBackend._executionOverlay(_injector);
  }

  @override
  void register<T extends Object>(
    Function constructor, {
    required Lifetime lifetime,
    String? key,
  }) {
    _ensureOpen();

    if (_committed) {
      throw StateError(
        'Constructor-backed services cannot be registered after commit.',
      );
    }

    switch (lifetime) {
      case Lifetime.factory:
        _injector.add<T>(constructor, key: key);
      case Lifetime.singleton:
        // AutoInjector starts singleton bindings during commit. Register them
        // as lazy first so module resources can be acquired before eager
        // initialization, then resolve them in activate().
        _injector.addLazySingleton<T>(constructor, key: key);
        _eagerInitializers.add(() {
          _injector.get<T>(key: key);
        });
      case Lifetime.lazySingleton:
        _injector.addLazySingleton<T>(constructor, key: key);
    }
  }

  @override
  void registerInstance<T extends Object>(T instance, {String? key}) {
    _ensureOpen();

    final wasCommitted = _committed;

    if (wasCommitted) {
      // Execution overlays commit through a temporary shell. Recommitting the
      // local injector is sufficient when a resource instance is installed and
      // keeps the long-lived parent untouched.
      _injector.uncommit();
      _committed = false;
    }

    Object? registrationError;
    StackTrace? registrationStackTrace;

    try {
      _injector.addInstance<T>(instance, key: key);
    } catch (error, stackTrace) {
      registrationError = error;
      registrationStackTrace = stackTrace;
    }

    if (wasCommitted) {
      _injector.commit();
      _committed = true;
    }

    if (registrationError != null) {
      Error.throwWithStackTrace(registrationError, registrationStackTrace!);
    }
  }

  @override
  T resolve<T extends Object>({String? key}) {
    _ensureOpen();

    if (!_committed) {
      commit();
    }

    return _injector.get<T>(key: key);
  }

  void _ensureOpen() {
    if (_closed) {
      throw const RuntimeClosedException();
    }
  }
}
