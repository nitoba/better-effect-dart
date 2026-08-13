part of '../../better_effect.dart';

/// The default [ResolverBackend], powered by `package:auto_injector`.
final class AutoInjectorBackend implements ResolverBackend {
  final AutoInjector _injector;

  final List<void Function()> _eagerInitializers = <void Function()>[];

  bool _committed = false;

  bool _activated = false;
  bool _closed = false;
  AutoInjectorBackend([AutoInjector? injector])
    : _injector = injector ?? AutoInjector();

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
    _injector.disposeRecursive();
  }

  @override
  void commit() {
    _ensureOpen();

    if (_committed) {
      return;
    }

    _injector.commit();
    _committed = true;
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
