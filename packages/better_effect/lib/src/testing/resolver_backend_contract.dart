import 'dart:async';

import 'package:better_effect/better_effect.dart';

/// Creates a fresh backend for one compatibility scenario.
typedef ResolverBackendTestFactory = ResolverBackend Function();

/// Creates a backend with backend-specific disposal instrumentation.
typedef ResolverBackendDisposalProbeFactory =
    ResolverBackendDisposalProbe Function();

/// Optional fixture used to prove that backend-owned instantiated services are
/// disposed when the backend closes.
///
/// The public [ResolverBackend] API intentionally does not prescribe a disposal
/// callback registration mechanism. Backend authors can expose their native
/// mechanism through this probe while every other scenario remains portable.
final class ResolverBackendDisposalProbe {
  const ResolverBackendDisposalProbe({
    required this.backend,
    required this.instantiate,
    required this.wasDisposed,
  });

  final ResolverBackend backend;

  /// Resolve or otherwise instantiate the service instrumented by this fixture.
  final Object Function() instantiate;

  /// Return whether the backend's native disposal callback was invoked.
  final bool Function() wasDisposed;
}

/// Behavioral scenarios shared by ResolverBackend implementations.
enum ResolverBackendContractCase {
  factoryCreatesFreshInstances,
  lazySingletonIsLazyAndStable,
  singletonActivatesEagerlyOnce,
  instancePreservesIdentity,
  keyedAndUnkeyedServicesRemainIsolated,
  constructorInjectionResolvesDependencies,
  missingDependencyFails,
  circularDependencyFails,
  duplicateRegistrationFails,
  commitIsIdempotent,
  activateIsIdempotent,
  constructorRegistrationAfterCommitFails,
  instanceRegistrationAfterCommitWorks,
  constructorDefectsArePreserved,
  partialRuntimeStartupFailureReleasesResources,
  closeIsIdempotent,
  resolveAfterCloseFails,
  instantiatedServicesAreDisposed,
  executionOverlayIsIsolated,
}

/// Result of one backend compatibility scenario.
final class ResolverBackendContractResult {
  const ResolverBackendContractResult({
    required this.scenario,
    required this.duration,
    required this.error,
    required this.stackTrace,
    required this.skipped,
    required this.skipReason,
  });

  final ResolverBackendContractCase scenario;
  final Duration duration;
  final Object? error;
  final StackTrace? stackTrace;
  final bool skipped;
  final String? skipReason;

  bool get passed => error == null && !skipped;

  bool get failed => error != null;
}

/// Complete compatibility report for one backend implementation.
final class ResolverBackendContractReport {
  ResolverBackendContractReport({
    required this.backendType,
    required Iterable<ResolverBackendContractResult> results,
  }) : results = List<ResolverBackendContractResult>.unmodifiable(results);

  final Type backendType;
  final List<ResolverBackendContractResult> results;

  Iterable<ResolverBackendContractResult> get failures {
    return results.where((result) => result.failed);
  }

  Iterable<ResolverBackendContractResult> get skipped {
    return results.where((result) => result.skipped);
  }

  bool get passed => failures.isEmpty;

  ResolverBackendContractResult resultFor(
    ResolverBackendContractCase scenario,
  ) {
    return results.singleWhere((result) => result.scenario == scenario);
  }

  /// Throw one aggregate exception when any required scenario failed.
  void throwIfFailed() {
    final values = failures.toList(growable: false);
    if (values.isNotEmpty) {
      throw ResolverBackendContractException(
        backendType: backendType,
        failures: values,
      );
    }
  }
}

/// Run every ResolverBackend scenario and return a detailed report.
///
/// Every scenario receives a fresh backend and closes it in `finally`.
/// Execution overlays and native disposal callbacks are optional capabilities;
/// their scenarios are reported as skipped when the matching factory is absent.
Future<ResolverBackendContractReport> inspectResolverBackendContract({
  required ResolverBackendTestFactory createBackend,
  ResolverBackendDisposalProbeFactory? createDisposalProbe,
}) async {
  final probe = createBackend();
  final backendType = probe.runtimeType;
  await Future<void>.sync(probe.close);

  final results = <ResolverBackendContractResult>[];
  for (final scenario in ResolverBackendContractCase.values) {
    results.add(
      await _runBackendScenario(
        createBackend,
        scenario,
        createDisposalProbe: createDisposalProbe,
      ),
    );
  }

  return ResolverBackendContractReport(
    backendType: backendType,
    results: results,
  );
}

/// Verify a backend contract and throw [ResolverBackendContractException] when
/// any required scenario fails.
Future<void> verifyResolverBackendContract({
  required ResolverBackendTestFactory createBackend,
  ResolverBackendDisposalProbeFactory? createDisposalProbe,
}) async {
  final report = await inspectResolverBackendContract(
    createBackend: createBackend,
    createDisposalProbe: createDisposalProbe,
  );
  report.throwIfFailed();
}

/// Acceptance-test-style alias intended for one ordinary `package:test` test.
///
/// ```dart
/// test('MyBackend follows the better_effect contract', () async {
///   await runResolverBackendContractTests(
///     createBackend: MyBackend.new,
///   );
/// });
/// ```
Future<void> runResolverBackendContractTests({
  required ResolverBackendTestFactory createBackend,
  ResolverBackendDisposalProbeFactory? createDisposalProbe,
}) {
  return verifyResolverBackendContract(
    createBackend: createBackend,
    createDisposalProbe: createDisposalProbe,
  );
}

Future<ResolverBackendContractResult> _runBackendScenario(
  ResolverBackendTestFactory createBackend,
  ResolverBackendContractCase scenario, {
  required ResolverBackendDisposalProbeFactory? createDisposalProbe,
}) async {
  ResolverBackend? backend;
  ResolverBackendDisposalProbe? disposalProbe;
  final stopwatch = Stopwatch()..start();
  Object? scenarioError;
  StackTrace? scenarioStackTrace;
  var skipped = false;
  String? skipReason;

  try {
    if (scenario ==
        ResolverBackendContractCase.instantiatedServicesAreDisposed) {
      final createProbe = createDisposalProbe;
      if (createProbe == null) {
        skipped = true;
        skipReason =
            'No ResolverBackendDisposalProbeFactory was provided for the '
            'backend-specific disposal callback.';
      } else {
        disposalProbe = createProbe();
        backend = disposalProbe.backend;
        await _verifyInstantiatedServiceDisposal(disposalProbe, scenario);
      }
    } else {
      backend = createBackend();
      if (scenario == ResolverBackendContractCase.executionOverlayIsIsolated &&
          backend is! ResolverBackendOverlayFactory) {
        skipped = true;
        skipReason =
            '${backend.runtimeType} does not implement '
            'ResolverBackendOverlayFactory.';
      } else {
        await _executeBackendScenario(backend, scenario);
      }
    }
  } catch (error, stackTrace) {
    scenarioError = error is ResolverBackendContractViolation
        ? error
        : ResolverBackendContractViolation(
            scenario: scenario,
            message: 'The scenario raised an unexpected error.',
            cause: error,
          );
    scenarioStackTrace = stackTrace;
  }

  final value = backend;
  if (value != null) {
    try {
      await Future<void>.sync(value.close);
    } catch (closeError, closeStackTrace) {
      final wrapped = ResolverBackendContractViolation(
        scenario: scenario,
        message: 'Backend cleanup failed after the scenario.',
        cause: closeError,
      );
      if (scenarioError == null) {
        scenarioError = wrapped;
        scenarioStackTrace = closeStackTrace;
      } else {
        scenarioError = CompositeDefect(
          primary: scenarioError,
          primaryStackTrace: scenarioStackTrace!,
          secondary: wrapped,
          secondaryStackTrace: closeStackTrace,
        );
      }
    }
  }

  stopwatch.stop();
  return ResolverBackendContractResult(
    scenario: scenario,
    duration: stopwatch.elapsed,
    error: scenarioError,
    stackTrace: scenarioStackTrace,
    skipped: skipped,
    skipReason: skipReason,
  );
}

Future<void> _executeBackendScenario(
  ResolverBackend backend,
  ResolverBackendContractCase scenario,
) async {
  switch (scenario) {
    case ResolverBackendContractCase.factoryCreatesFreshInstances:
      backend.register<_ContractFactoryService>(
        _ContractFactoryService.new,
        lifetime: Lifetime.factory,
      );
      backend.commit();
      final first = backend.resolve<_ContractFactoryService>();
      final second = backend.resolve<_ContractFactoryService>();
      _contractExpect(
        scenario,
        !identical(first, second),
        'Factory reused the same instance.',
      );

    case ResolverBackendContractCase.lazySingletonIsLazyAndStable:
      var creations = 0;
      backend.register<_ContractLazyService>(() {
        creations++;
        return const _ContractLazyService();
      }, lifetime: Lifetime.lazySingleton);
      backend.commit();
      await Future<void>.sync(backend.activate);
      _contractExpect(
        scenario,
        creations == 0,
        'Lazy singleton was created eagerly.',
      );
      final first = backend.resolve<_ContractLazyService>();
      final second = backend.resolve<_ContractLazyService>();
      _contractExpect(
        scenario,
        creations == 1,
        'Lazy singleton was created more than once.',
      );
      _contractExpect(
        scenario,
        identical(first, second),
        'Lazy singleton identity changed.',
      );

    case ResolverBackendContractCase.singletonActivatesEagerlyOnce:
      var creations = 0;
      backend.register<_ContractSingletonService>(() {
        creations++;
        return const _ContractSingletonService();
      }, lifetime: Lifetime.singleton);
      backend.commit();
      _contractExpect(
        scenario,
        creations == 0,
        'Singleton was created before activate().',
      );
      await Future<void>.sync(backend.activate);
      await Future<void>.sync(backend.activate);
      _contractExpect(
        scenario,
        creations == 1,
        'Singleton activation was not idempotent.',
      );
      final first = backend.resolve<_ContractSingletonService>();
      final second = backend.resolve<_ContractSingletonService>();
      _contractExpect(
        scenario,
        identical(first, second),
        'Singleton identity changed.',
      );

    case ResolverBackendContractCase.instancePreservesIdentity:
      const instance = _ContractInstanceService();
      backend.registerInstance<_ContractInstanceService>(instance);
      backend.commit();
      _contractExpect(
        scenario,
        identical(backend.resolve<_ContractInstanceService>(), instance),
        'Registered instance identity changed.',
      );

    case ResolverBackendContractCase.keyedAndUnkeyedServicesRemainIsolated:
      const unkeyed = _ContractNamedService('unkeyed');
      const first = _ContractNamedService('first');
      const second = _ContractNamedService('second');
      backend.registerInstance<_ContractNamedService>(unkeyed);
      backend.registerInstance<_ContractNamedService>(first, key: 'first');
      backend.registerInstance<_ContractNamedService>(second, key: 'second');
      backend.commit();
      _contractExpect(
        scenario,
        identical(backend.resolve<_ContractNamedService>(), unkeyed),
        'Unkeyed service was shadowed by a keyed registration.',
      );
      _contractExpect(
        scenario,
        identical(backend.resolve<_ContractNamedService>(key: 'first'), first),
        'First keyed service resolved incorrectly.',
      );
      _contractExpect(
        scenario,
        identical(
          backend.resolve<_ContractNamedService>(key: 'second'),
          second,
        ),
        'Second keyed service resolved incorrectly.',
      );

    case ResolverBackendContractCase.constructorInjectionResolvesDependencies:
      const dependency = _ContractDependency();
      backend.registerInstance<_ContractDependency>(dependency);
      backend.register<_ContractDependentService>(
        _ContractDependentService.new,
        lifetime: Lifetime.lazySingleton,
      );
      backend.commit();
      final service = backend.resolve<_ContractDependentService>();
      _contractExpect(
        scenario,
        identical(service.dependency, dependency),
        'Constructor dependency was not injected.',
      );

    case ResolverBackendContractCase.missingDependencyFails:
      backend.register<_ContractDependentService>(
        _ContractDependentService.new,
        lifetime: Lifetime.lazySingleton,
      );
      backend.commit();
      final error = _captureError(backend.resolve<_ContractDependentService>);
      _contractExpect(
        scenario,
        error != null,
        'Resolving a constructor with a missing dependency succeeded.',
      );

    case ResolverBackendContractCase.circularDependencyFails:
      backend.register<_ContractCircularA>(
        _ContractCircularA.new,
        lifetime: Lifetime.lazySingleton,
      );
      backend.register<_ContractCircularB>(
        _ContractCircularB.new,
        lifetime: Lifetime.lazySingleton,
      );
      backend.commit();
      final error = _captureError(backend.resolve<_ContractCircularA>);
      _contractExpect(
        scenario,
        error != null,
        'Resolving a circular constructor graph succeeded.',
      );

    case ResolverBackendContractCase.duplicateRegistrationFails:
      Object? error;
      try {
        backend.register<_ContractFactoryService>(
          _ContractFactoryService.new,
          lifetime: Lifetime.factory,
        );
        backend.register<_ContractFactoryService>(
          _ContractFactoryService.new,
          lifetime: Lifetime.factory,
        );
        backend.commit();
      } catch (caught) {
        error = caught;
      }
      _contractExpect(
        scenario,
        error != null,
        'A duplicate unkeyed service identity was accepted.',
      );

    case ResolverBackendContractCase.commitIsIdempotent:
      backend.register<_ContractFactoryService>(
        _ContractFactoryService.new,
        lifetime: Lifetime.factory,
      );
      backend.commit();
      backend.commit();
      backend.resolve<_ContractFactoryService>();

    case ResolverBackendContractCase.activateIsIdempotent:
      var creations = 0;
      backend.register<_ContractSingletonService>(() {
        creations++;
        return const _ContractSingletonService();
      }, lifetime: Lifetime.singleton);
      backend.commit();
      await Future<void>.sync(backend.activate);
      await Future<void>.sync(backend.activate);
      _contractExpect(
        scenario,
        creations == 1,
        'activate() repeated eager creation.',
      );

    case ResolverBackendContractCase.constructorRegistrationAfterCommitFails:
      backend.commit();
      final error = _captureError(
        () => backend.register<_ContractFactoryService>(
          _ContractFactoryService.new,
          lifetime: Lifetime.factory,
        ),
      );
      _contractExpect(
        scenario,
        error != null,
        'Constructor registration succeeded after commit().',
      );

    case ResolverBackendContractCase.instanceRegistrationAfterCommitWorks:
      backend.commit();
      const instance = _ContractInstanceService();
      backend.registerInstance<_ContractInstanceService>(instance);
      _contractExpect(
        scenario,
        identical(backend.resolve<_ContractInstanceService>(), instance),
        'A resource-style instance registered after commit was not resolvable.',
      );

    case ResolverBackendContractCase.constructorDefectsArePreserved:
      final expected = StateError('contract-constructor-defect');
      backend.register<_ContractThrowingService>(() {
        throw expected;
      }, lifetime: Lifetime.lazySingleton);
      backend.commit();
      final actual = _captureError(backend.resolve<_ContractThrowingService>);
      _contractExpect(
        scenario,
        actual != null,
        'Constructor defect was swallowed.',
      );
      _contractExpect(
        scenario,
        identical(actual, expected) || actual.toString().contains('$expected'),
        'Constructor defect lost its original cause.',
        cause: actual,
      );

    case ResolverBackendContractCase
        .partialRuntimeStartupFailureReleasesResources:
      var releases = 0;
      final module = Module([
        .resource<_ContractFirstResource>(
          acquire: (_) async => const _ContractFirstResource(),
          release: (_, _) {
            releases++;
          },
        ),
        .resource<_ContractFailingResource>(
          acquire: (_) async => throw StateError('startup failed'),
          release: (_, _) {
            throw StateError('unreachable release');
          },
        ),
      ]);
      final error = await _captureAsyncError(
        () => module.start(backend: backend),
      );
      _contractExpect(
        scenario,
        error != null,
        'Runtime startup unexpectedly succeeded.',
      );
      _contractExpect(
        scenario,
        releases == 1,
        'A resource acquired before startup failure was not released exactly once.',
      );

    case ResolverBackendContractCase.closeIsIdempotent:
      backend.commit();
      await Future<void>.sync(backend.close);
      await Future<void>.sync(backend.close);

    case ResolverBackendContractCase.resolveAfterCloseFails:
      backend.register<_ContractFactoryService>(
        _ContractFactoryService.new,
        lifetime: Lifetime.factory,
      );
      backend.commit();
      await Future<void>.sync(backend.close);
      final error = _captureError(backend.resolve<_ContractFactoryService>);
      _contractExpect(
        scenario,
        error != null,
        'Resolution succeeded after close().',
      );

    case ResolverBackendContractCase.instantiatedServicesAreDisposed:
      throw StateError('Disposal scenarios require a disposal probe.');

    case ResolverBackendContractCase.executionOverlayIsIsolated:
      await _verifyExecutionOverlay(backend, scenario);
  }
}

Future<void> _verifyInstantiatedServiceDisposal(
  ResolverBackendDisposalProbe probe,
  ResolverBackendContractCase scenario,
) async {
  probe.backend.commit();
  await Future<void>.sync(probe.backend.activate);
  probe.instantiate();
  await Future<void>.sync(probe.backend.close);
  _contractExpect(
    scenario,
    probe.wasDisposed(),
    'The backend closed without invoking its native disposal callback for an '
    'instantiated service.',
  );
}

Future<void> _verifyExecutionOverlay(
  ResolverBackend backend,
  ResolverBackendContractCase scenario,
) async {
  final factory = backend as ResolverBackendOverlayFactory;
  const rootOnly = _ContractRootOnlyService();
  const rootMessage = _ContractNamedService('root');
  backend.registerInstance<_ContractRootOnlyService>(rootOnly);
  backend.registerInstance<_ContractNamedService>(rootMessage);
  backend.commit();

  final overlay = factory.createExecutionOverlay();
  const localOnly = _ContractLocalOnlyService();
  const localMessage = _ContractNamedService('local');
  const keyedRoot = _ContractNamedService('keyed-root');

  try {
    overlay.registerInstance<_ContractLocalOnlyService>(localOnly);
    overlay.registerInstance<_ContractNamedService>(localMessage);
    overlay.registerInstance<_ContractNamedService>(keyedRoot, key: 'local');
    overlay.commit();
    await Future<void>.sync(overlay.activate);

    _contractExpect(
      scenario,
      identical(overlay.resolve<_ContractLocalOnlyService>(), localOnly),
      'Overlay could not resolve a local service.',
    );
    _contractExpect(
      scenario,
      identical(overlay.resolve<_ContractRootOnlyService>(), rootOnly),
      'Overlay could not fall back to the root backend.',
    );
    _contractExpect(
      scenario,
      identical(overlay.resolve<_ContractNamedService>(), localMessage),
      'Overlay did not shadow the root service.',
    );
    _contractExpect(
      scenario,
      identical(
        overlay.resolve<_ContractNamedService>(key: 'local'),
        keyedRoot,
      ),
      'Overlay keyed resolution was not isolated.',
    );
    _contractExpect(
      scenario,
      identical(backend.resolve<_ContractNamedService>(), rootMessage),
      'Overlay mutated the root service.',
    );
  } finally {
    await Future<void>.sync(overlay.close);
  }

  _contractExpect(
    scenario,
    identical(backend.resolve<_ContractRootOnlyService>(), rootOnly),
    'Closing the overlay closed or mutated the root backend.',
  );
}

Object? _captureError(void Function() operation) {
  try {
    operation();
    return null;
  } catch (error) {
    return error;
  }
}

Future<Object?> _captureAsyncError(
  FutureOr<Object> Function() operation,
) async {
  try {
    await operation();
    return null;
  } catch (error) {
    return error;
  }
}

void _contractExpect(
  ResolverBackendContractCase scenario,
  bool condition,
  String message, {
  Object? cause,
}) {
  if (condition) return;
  throw ResolverBackendContractViolation(
    scenario: scenario,
    message: message,
    cause: cause,
  );
}

final class _ContractFactoryService {}

final class _ContractLazyService {
  const _ContractLazyService();
}

final class _ContractSingletonService {
  const _ContractSingletonService();
}

final class _ContractInstanceService {
  const _ContractInstanceService();
}

final class _ContractNamedService {
  const _ContractNamedService(this.value);

  final String value;
}

final class _ContractDependency {
  const _ContractDependency();
}

final class _ContractDependentService {
  const _ContractDependentService(this.dependency);

  final _ContractDependency dependency;
}

final class _ContractCircularA {
  const _ContractCircularA(this.dependency);

  final _ContractCircularB dependency;
}

final class _ContractCircularB {
  const _ContractCircularB(this.dependency);

  final _ContractCircularA dependency;
}

final class _ContractThrowingService {}

final class _ContractFirstResource {
  const _ContractFirstResource();
}

final class _ContractFailingResource {
  const _ContractFailingResource();
}

final class _ContractRootOnlyService {
  const _ContractRootOnlyService();
}

final class _ContractLocalOnlyService {
  const _ContractLocalOnlyService();
}

/// One failed contract assertion.
final class ResolverBackendContractViolation implements Exception {
  const ResolverBackendContractViolation({
    required this.scenario,
    required this.message,
    this.cause,
  });

  final ResolverBackendContractCase scenario;
  final String message;
  final Object? cause;

  @override
  String toString() {
    final suffix = cause == null ? '' : ' Cause: $cause';
    return '${scenario.name}: $message$suffix';
  }
}

/// Aggregate failure raised by [verifyResolverBackendContract].
final class ResolverBackendContractException implements Exception {
  ResolverBackendContractException({
    required this.backendType,
    required Iterable<ResolverBackendContractResult> failures,
  }) : failures = List<ResolverBackendContractResult>.unmodifiable(failures);

  final Type backendType;
  final List<ResolverBackendContractResult> failures;

  @override
  String toString() {
    final details = failures
        .map((failure) => '${failure.scenario.name}: ${failure.error}')
        .join('; ');
    return '$backendType failed ${failures.length} ResolverBackend '
        'contract scenario(s): $details';
  }
}
