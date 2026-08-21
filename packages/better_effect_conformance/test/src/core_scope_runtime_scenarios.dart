import 'package:better_effect/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'registry.dart';

final class _ScopeResource {
  const _ScopeResource(this.name);

  final String name;
}

final class _ScopeCleanupFailure implements Exception {
  const _ScopeCleanupFailure(this.label);

  final String label;
}

final class _ParentService {
  const _ParentService(this.value);

  final String value;
}

final class _SharedService {
  const _SharedService(this.value);

  final String value;
}

void registerCoreScopeRuntimeScenarios() {
  conformanceTest('SCOPE-01', () async {
    final events = <String>[];
    final root = Scope.make();
    final first = root.fork();
    final second = root.fork();
    final grandchild = second.fork();

    root.addFinalizer((_) => events.add('root:first'));
    root.addFinalizer((_) => events.add('root:second'));
    first.addFinalizer((_) => events.add('child:first'));
    second.addFinalizer((_) => events.add('child:second'));
    grandchild.addFinalizer((_) => events.add('grandchild'));

    await root.close(const ExitInterrupted<Object, Object>());

    expect(events, <String>[
      'grandchild',
      'child:second',
      'child:first',
      'root:second',
      'root:first',
    ]);
  });

  conformanceTest('SCOPE-02', () async {
    final scope = Scope.make();
    final started = TestSignal();
    final continueAcquisition = TestSignal();
    var releases = 0;
    Exit<Object, Object>? releaseOutcome;
    const outcome = ExitInterrupted<Object, Object>();

    final acquisition = scope.acquire(
      () async {
        started.signal();
        await continueAcquisition.wait;
        return const _ScopeResource('late');
      },
      (_, exit) {
        releases++;
        releaseOutcome = exit;
      },
    );

    await started.wait;
    final closing = scope.close(outcome);
    continueAcquisition.signal();

    await expectLater(acquisition, throwsA(isA<ScopeClosedException>()));
    await closing;
    expect(releases, 1);
    expect(releaseOutcome, same(outcome));
  });

  conformanceTest('SCOPE-03', () async {
    final scope = Scope.make();
    final outcome = ExitFailure<Object, Object>(
      const _ScopeCleanupFailure('x'),
    );
    Exit<Object, Object>? observed;

    await scope.acquire(() => const _ScopeResource('owned'), (_, exit) {
      observed = exit;
    });
    await scope.close(outcome);

    expect(observed, same(outcome));
  });

  conformanceTest('SCOPE-04', () async {
    final root = Scope.make();
    final first = root.fork();
    final second = root.fork();

    root.addFinalizer((_) => throw const _ScopeCleanupFailure('root:first'));
    root.addFinalizer((_) => throw const _ScopeCleanupFailure('root:second'));
    first.addFinalizer((_) => throw const _ScopeCleanupFailure('child:first'));
    second.addFinalizer(
      (_) => throw const _ScopeCleanupFailure('child:second'),
    );

    ScopeReleaseException? failure;
    try {
      await root.close(const ExitInterrupted<Object, Object>());
    } on ScopeReleaseException catch (error) {
      failure = error;
    }

    expect(failure, isNotNull);
    expect(
      failure!.failures
          .map((item) => (item.error as _ScopeCleanupFailure).label)
          .toList(),
      <String>['child:second', 'child:first', 'root:second', 'root:first'],
    );
  });

  conformanceTest('SCOPE-05', () async {
    final scope = Scope.make();
    final gate = TestSignal();
    var finalizerCalls = 0;
    scope.addFinalizer((_) async {
      finalizerCalls++;
      await gate.wait;
    });

    final first = scope.close(const ExitInterrupted<Object, Object>());
    final second = scope.close(const ExitInterrupted<Object, Object>());

    expect(identical(first, second), isTrue);
    gate.signal();
    await first;
    await second;
    expect(finalizerCalls, 1);
  });

  conformanceTest('SCOPE-06', () async {
    final scope = Scope.make();
    await scope.close(const ExitInterrupted<Object, Object>());

    expect(() => scope.fork(), throwsA(isA<ScopeClosedException>()));
    expect(
      () => scope.addFinalizer((_) {}),
      throwsA(isA<ScopeClosedException>()),
    );
    await expectLater(
      scope.acquire(() => const _ScopeResource('late'), (_, _) {}),
      throwsA(isA<ScopeClosedException>()),
    );
  });

  conformanceTest('RUNTIME-01', () async {
    final runtime = await Module(const <Binding>[]).start();
    final closing = runtime.close();

    expect(runtime.state, RuntimeState.closing);
    expect(runtime.isClosed, isTrue);
    expect(() => runtime.services, throwsA(isA<RuntimeClosedException>()));
    expect(
      () => runtime.execute(Effect<Unit, Never>.succeed(unit)),
      throwsA(isA<RuntimeClosedException>()),
    );

    await closing;
    expect(runtime.state, RuntimeState.closed);
  });

  conformanceTest('RUNTIME-02', () async {
    final runtime = await Module(const <Binding>[]).start();
    final started = TestSignal();
    Object? cancellationReason;
    final execution = runtime.execute(
      Effect<Unit, Never>.result((use) async {
        started.signal();
        await use.cancellation.whenCancelled;
        cancellationReason = use.cancellation.reason;
        use.cancellation.throwIfCancelled();
        return unit;
      }),
    );

    await started.wait;
    await runtime.close(
      gracePeriod: Duration.zero,
      interruptAfterGracePeriod: true,
    );

    expect(cancellationReason, 'runtime-shutdown');
    expect(await execution.exit, isExitInterrupted<Unit, Never>());
    expect(runtime.state, RuntimeState.closed);
  });

  conformanceTest('RUNTIME-03', () async {
    final started = TestSignal();
    final continuePhysicalWork = TestSignal();
    final cancellationObserved = TestSignal();
    var runtimeReleases = 0;
    final runtime = await Module([
      .resource<_ScopeResource>(
        acquire: (_) async => const _ScopeResource('runtime'),
        release: (_, _) {
          runtimeReleases++;
        },
      ),
    ]).start();
    final execution = runtime.execute(
      Effect<int, Never>.result((use) async {
        started.signal();
        await use.cancellation.whenCancelled;
        cancellationObserved.signal();
        await continuePhysicalWork.wait;
        return 42;
      }),
    );

    await started.wait;
    final closing = runtime.close(
      gracePeriod: Duration.zero,
      interruptAfterGracePeriod: true,
    );
    await cancellationObserved.wait;

    expect(execution.isRunning, isTrue);
    expect(runtimeReleases, 0);
    continuePhysicalWork.signal();

    expect(expectExitSuccess(await execution.exit), 42);
    await closing;
    expect(runtimeReleases, 1);
    expect(runtime.state, RuntimeState.closed);
  });

  conformanceTest('RUNTIME-04', () async {
    final started = TestSignal();
    final continueExecution = TestSignal();
    final events = <String>[];
    final runtime = await Module([
      .resource<_ParentService>(
        acquire: (_) async => const _ParentService('root'),
        release: (_, _) {
          events.add('release:runtime');
        },
      ),
    ]).start();
    final execution = runtime.execute(
      Effect<String, Never>.result((use) async {
        started.signal();
        await continueExecution.wait;
        final service = use<_ParentService>();
        await use.acquire(
          Effect<_ScopeResource, Never>.succeed(
            const _ScopeResource('execution'),
          ),
          release: (_, _) {
            events.add('release:execution');
          },
        );
        return service.value;
      }),
    );

    await started.wait;
    final closing = runtime.close();
    expect(runtime.state, RuntimeState.closing);
    expect(() => runtime.services, throwsA(isA<RuntimeClosedException>()));

    continueExecution.signal();
    expect(expectExitSuccess(await execution.exit), 'root');
    await closing;
    expect(events, <String>['release:execution', 'release:runtime']);
  });

  conformanceTest('RUNTIME-05', () async {
    final acquisitionStarted = TestSignal();
    final continueAcquisition = TestSignal();
    var releases = 0;
    final runtime = await Module(const <Binding>[]).start();
    final execution = runtime.execute(
      Effect<String, _ScopeCleanupFailure>.result((use) async {
        final resource = await use.acquire(
          Effect<_ScopeResource, _ScopeCleanupFailure>.result((_) async {
            acquisitionStarted.signal();
            await continueAcquisition.wait;
            return const _ScopeResource('late');
          }),
          release: (_, _) {
            releases++;
          },
        );
        return resource.name;
      }).timeout(
        Duration.zero,
        onTimeout: () => const _ScopeCleanupFailure('timeout'),
      ),
    );

    await acquisitionStarted.wait;
    expect(await execution.exit, isExitFailure<String, _ScopeCleanupFailure>());
    expect(execution.isRunning, isTrue);
    expect(releases, 0);

    continueAcquisition.signal();
    await runtime.close();
    expect(releases, 1);
    expect(execution.isRunning, isFalse);
  });

  conformanceTest('ENV-01', () async {
    final runtime = await Module([
      .instance<_ParentService>(const _ParentService('parent')),
      .instance<_SharedService>(const _SharedService('root')),
    ]).start();

    final exit = await runtime.runExitWith(
      Module([.instance<_SharedService>(const _SharedService('execution'))]),
      Effect<(String, String), Never>.result((use) async {
        return (use<_ParentService>().value, use<_SharedService>().value);
      }),
    );

    expect(expectExitSuccess(exit), ('parent', 'execution'));
    expect(runtime.services<_SharedService>().value, 'root');
    await runtime.close();
  });

  conformanceTest('ENV-02', () async {
    final root = await Module([
      .instance<_ParentService>(const _ParentService('parent')),
      .instance<_SharedService>(const _SharedService('root')),
    ]).start();
    final child = await root.fork(
      Module([.instance<_SharedService>(const _SharedService('child'))]),
    );

    expect(child.services<_ParentService>().value, 'parent');
    expect(child.services<_SharedService>().value, 'child');
    expect(root.services<_SharedService>().value, 'root');

    await child.close();
    expect(root.state, RuntimeState.active);
    await root.close();
  });

  conformanceTest('ENV-03', () async {
    final events = <String>[];
    final root = await Module([
      .resource<_ParentService>(
        acquire: (_) async => const _ParentService('root'),
        release: (_, _) {
          events.add('release:parent');
        },
      ),
    ]).start();
    final child = await root.fork(
      Module([
        .resource<_SharedService>(
          acquire: (_) async => const _SharedService('child'),
          release: (_, _) {
            events.add('release:child');
          },
        ),
      ]),
    );

    await root.close();

    expect(events, <String>['release:child', 'release:parent']);
    expect(child.state, RuntimeState.closed);
    expect(root.state, RuntimeState.closed);
  });
}
