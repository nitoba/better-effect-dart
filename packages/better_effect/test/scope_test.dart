import 'dart:async';

import 'package:better_effect/better_effect.dart';
import 'package:test/test.dart';

final class Resource {
  const Resource(this.name);

  final String name;
}

final class CleanupError implements Exception {
  const CleanupError();
}

final class AuthenticationFailure implements Exception {
  const AuthenticationFailure();
}

void main() {
  group('Scope ownership', () {
    const outcome = ExitInterrupted<Object, Object>();

    test('closes children and finalizers in reverse creation order', () async {
      final events = <String>[];
      final root = Scope.make();
      final first = root.fork();
      final second = root.fork();
      final grandchild = second.fork();

      root.addFinalizer((_) => events.add('root'));
      first.addFinalizer((_) => events.add('first'));
      second.addFinalizer((_) => events.add('second'));
      grandchild.addFinalizer((_) => events.add('grandchild'));

      await root.close(outcome);

      expect(events, ['grandchild', 'second', 'first', 'root']);
    });

    test('concurrent close callers share the same completion', () async {
      final scope = Scope.make();
      final gate = Completer<void>();
      scope.addFinalizer((_) => gate.future);

      final first = scope.close(outcome);
      final second = scope.close(outcome);

      expect(identical(first, second), isTrue);

      gate.complete();
      await first;
    });

    test('release receives the outcome that closes the Scope', () async {
      final scope = Scope.make();
      final expected = ExitFailure<Object, Object>(
        const AuthenticationFailure(),
      );
      Exit<Object, Object>? observed;

      await scope.acquire(() => const Resource('scoped'), (_, exit) {
        observed = exit;
      });

      await scope.close(expected);

      expect(observed, same(expected));
    });

    test('releases an acquisition that completes after close begins', () async {
      final scope = Scope.make();
      final started = Completer<void>();
      final continueAcquisition = Completer<void>();
      Exit<Object, Object>? observed;
      var released = false;

      final acquisition = scope.acquire(
        () async {
          started.complete();
          await continueAcquisition.future;
          return const Resource('late');
        },
        (_, exit) {
          released = true;
          observed = exit;
        },
      );

      await started.future;
      final closing = scope.close(outcome);
      continueAcquisition.complete();

      await expectLater(acquisition, throwsA(isA<ScopeClosedException>()));
      await closing;

      expect(released, isTrue);
      expect(observed, same(outcome));
    });

    test('preserves registration and immediate release failures', () async {
      final scope = Scope.make();
      final started = Completer<void>();
      final continueAcquisition = Completer<void>();

      final acquisition = scope.acquire(() async {
        started.complete();
        await continueAcquisition.future;
        return const Resource('late');
      }, (_, _) => throw const CleanupError());

      await started.future;
      final closing = scope.close(outcome);
      continueAcquisition.complete();

      await expectLater(acquisition, throwsA(isA<CompositeDefect>()));
      await closing;
    });

    test('aggregates failures from children and finalizers', () async {
      final root = Scope.make();
      final child = root.fork();

      root.addFinalizer((_) => throw StateError('root:first'));
      root.addFinalizer((_) => throw StateError('root:second'));
      child.addFinalizer((_) => throw StateError('child'));

      await expectLater(
        root.close(outcome),
        throwsA(
          isA<ScopeReleaseException>().having(
            (error) => error.failures,
            'failures',
            hasLength(3),
          ),
        ),
      );
    });

    test('a closed child detaches from its parent', () async {
      final root = Scope.make();
      final child = root.fork();
      var releases = 0;

      child.addFinalizer((_) {
        releases++;
      });

      await child.close(outcome);
      await root.close(outcome);

      expect(releases, 1);
    });

    test('rejects new work after close begins', () async {
      final scope = Scope.make();
      var acquisitionAttempted = false;

      await scope.close(outcome);

      expect(scope.fork, throwsA(isA<ScopeClosedException>()));
      expect(
        () => scope.addFinalizer((_) {}),
        throwsA(isA<ScopeClosedException>()),
      );
      await expectLater(
        scope.acquire(() {
          acquisitionAttempted = true;
          return const Resource('unexpected');
        }, (_, _) {}),
        throwsA(isA<ScopeClosedException>()),
      );

      expect(acquisitionAttempted, isFalse);
    });
  });

  test('module resources are released in reverse acquisition order', () async {
    final events = <String>[];

    final module = Module([
      .resource<Resource>(
        acquire: (_) async {
          events.add('acquire:first');
          return const Resource('first');
        },
        release: (resource, _) async {
          events.add('release:${resource.name}');
        },
        key: const ServiceKey<Resource>('first'),
      ),
      .resource<Resource>(
        acquire: (_) async {
          events.add('acquire:second');
          return const Resource('second');
        },
        release: (resource, _) async {
          events.add('release:${resource.name}');
        },
        key: const ServiceKey<Resource>('second'),
      ),
    ]);

    final result = await module.run(Effect<Unit, Never>.succeed(unit));

    expect(result.isSuccess(), isTrue);
    expect(events, [
      'acquire:first',
      'acquire:second',
      'release:second',
      'release:first',
    ]);
  });

  test('use.acquire releases execution resources after runtime.run', () async {
    var released = false;

    final runtime = await Module(const <Binding>[]).start();

    try {
      final effect = Effect<String, Never>.result((use) async {
        final resource = await use.acquire(
          Effect<Resource, Never>.succeed(const Resource('execution')),
          release: (_, _) async {
            released = true;
          },
        );

        return resource.name;
      });

      final result = await runtime.run(effect);

      expect(result.getOrNull(), 'execution');
      expect(released, isTrue);
    } finally {
      await runtime.close();
    }
  });

  test('cleanup failure preserves typed execution failure', () async {
    final diagnostics = <CleanupFailureDiagnostic>[];
    final runtime = await Module(const <Binding>[]).start(
      cleanupFailureObserver: (diagnostic) {
        diagnostics.add(diagnostic);
        throw StateError('observer failed');
      },
    );

    try {
      final exit = await runtime.runExit(
        Effect<String, AuthenticationFailure>.result((use) async {
          await use.acquire(
            Effect<Resource, AuthenticationFailure>.succeed(
              const Resource('execution'),
            ),
            release: (_, _) => throw const CleanupError(),
          );
          use.fail(const AuthenticationFailure());
        }),
        executionLabel: 'authenticate',
      );

      expect(exit, isA<ExitFailure<String, AuthenticationFailure>>());
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.outcome, same(exit));
      expect(diagnostics.single.error, isA<ScopeReleaseException>());
      expect(diagnostics.single.executionId, 1);
      expect(diagnostics.single.executionLabel, 'authenticate');
    } finally {
      await runtime.close();
    }
  });

  test('cleanup failure turns execution success into a defect', () async {
    final diagnostics = <CleanupFailureDiagnostic>[];
    final runtime = await Module(
      const <Binding>[],
    ).start(cleanupFailureObserver: diagnostics.add);

    try {
      final exit = await runtime.runExit(
        Effect<String, Never>.result((use) async {
          return (await use.acquire(
            Effect<Resource, Never>.succeed(const Resource('execution')),
            release: (_, _) => throw const CleanupError(),
          )).name;
        }),
      );

      expect(exit, isA<ExitDefect<String, Never>>());
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.outcome, isA<ExitSuccess<String, Never>>());
      expect(diagnostics.single.executionId, 1);
    } finally {
      await runtime.close();
    }
  });

  test('cleanup failure is aggregated after an execution defect', () async {
    final diagnostics = <CleanupFailureDiagnostic>[];
    final runtime = await Module(
      const <Binding>[],
    ).start(cleanupFailureObserver: diagnostics.add);

    try {
      final exit = await runtime.runExit(
        Effect<String, Never>.result((use) async {
          await use.acquire(
            Effect<Resource, Never>.succeed(const Resource('execution')),
            release: (_, _) => throw const CleanupError(),
          );
          throw const AuthenticationFailure();
        }),
      );

      expect(exit, isA<ExitDefect<String, Never>>());
      expect(
        (exit as ExitDefect<String, Never>).defect,
        isA<CompositeDefect>(),
      );
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.outcome, isA<ExitDefect<String, Never>>());
    } finally {
      await runtime.close();
    }
  });

  test(
    'Module.runExit preserves typed failure when runtime cleanup fails',
    () async {
      final diagnostics = <CleanupFailureDiagnostic>[];
      final exit =
          await Module([
            .resource<Resource>(
              acquire: (_) async => const Resource('runtime'),
              release: (_, _) => throw const CleanupError(),
            ),
          ]).runExit(
            Effect<String, AuthenticationFailure>.fail(
              const AuthenticationFailure(),
            ),
            cleanupFailureObserver: diagnostics.add,
          );

      expect(exit, isA<ExitFailure<String, AuthenticationFailure>>());
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.outcome, same(exit));
      expect(diagnostics.single.executionId, 0);
      expect(diagnostics.single.executionLabel, isNull);
    },
  );

  test(
    'Runtime.close drains active executions before module resources',
    () async {
      final events = <String>[];
      final started = Completer<void>();
      final continueExecution = Completer<void>();

      final module = Module([
        .resource<Resource>(
          acquire: (_) async {
            events.add('acquire:runtime');
            return const Resource('runtime');
          },
          release: (_, _) async {
            events.add('release:runtime');
          },
        ),
      ]);
      final runtime = await module.start();

      final running = runtime.runExit(
        Effect<Resource, Never>.result((use) async {
          use<Resource>();
          started.complete();
          await continueExecution.future;
          events.add('resolve:after-closing');
          await use.acquire(
            Effect<Resource, Never>.succeed(const Resource('execution')),
            release: (_, _) async {
              events.add('release:execution');
            },
          );
          events.add('acquire:after-closing');
          return use<Resource>();
        }),
      );

      await started.future;

      final closing = runtime.close();

      expect(runtime.state, RuntimeState.closing);
      expect(runtime.isClosed, isTrue);
      expect(events, ['acquire:runtime']);
      expect(() => runtime.services, throwsA(isA<RuntimeClosedException>()));

      await expectLater(
        runtime.run(Effect<Unit, Never>.succeed(unit)),
        throwsA(isA<RuntimeClosedException>()),
      );

      continueExecution.complete();

      final exit = await running;
      await closing;

      expect(exit, isA<ExitSuccess<Resource, Never>>());
      expect(runtime.state, RuntimeState.closed);
      expect(events, [
        'acquire:runtime',
        'resolve:after-closing',
        'acquire:after-closing',
        'release:execution',
        'release:runtime',
      ]);
    },
  );

  test(
    'execution resources close before module resources during shutdown',
    () async {
      final events = <String>[];
      final acquired = Completer<void>();
      final continueExecution = Completer<void>();

      final module = Module([
        .resource<Resource>(
          acquire: (_) async {
            events.add('acquire:runtime');
            return const Resource('runtime');
          },
          release: (_, _) async {
            events.add('release:runtime');
          },
        ),
      ]);
      final runtime = await module.start();

      final running = runtime.run(
        Effect<Unit, Never>.result((use) async {
          await use.acquire(
            Effect<Resource, Never>.succeed(const Resource('execution')),
            release: (_, _) async {
              events.add('release:execution');
            },
          );
          acquired.complete();
          await continueExecution.future;
          return unit;
        }),
      );

      await acquired.future;
      final closing = runtime.close();

      expect(events, ['acquire:runtime']);

      continueExecution.complete();
      await running;
      await closing;

      expect(events, [
        'acquire:runtime',
        'release:execution',
        'release:runtime',
      ]);
    },
  );

  test(
    'Runtime.close requests cooperative cancellation after the grace period',
    () async {
      final started = Completer<void>();
      var cancellationObserved = false;

      final runtime = await Module(const <Binding>[]).start();
      final running = runtime.run(
        Effect<Unit, Never>.result((use) async {
          started.complete();
          await use.cancellation.whenCancelled;
          cancellationObserved = use.cancellation.isCancelled;
          return unit;
        }),
      );

      await started.future;
      await runtime.close(
        gracePeriod: Duration.zero,
        interruptAfterGracePeriod: true,
      );

      await running;
      expect(cancellationObserved, isTrue);
      expect(runtime.state, RuntimeState.closed);
    },
  );

  test(
    'timeout keeps the physical Scope alive until the source Future ends',
    () async {
      final acquisitionStarted = Completer<void>();
      final continueAcquisition = Completer<void>();
      var released = false;

      final runtime = await Module(const <Binding>[]).start();
      final running = runtime.runExit(
        Effect<String, String>.result((use) async {
          final resource = await use.acquire(
            Effect<Resource, String>.result((_) async {
              acquisitionStarted.complete();
              await continueAcquisition.future;
              return const Resource('late');
            }),
            release: (_, _) async {
              released = true;
            },
          );

          return resource.name;
        }).timeout(Duration.zero, onTimeout: () => 'timeout'),
      );

      await acquisitionStarted.future;
      final exit = await running.timeout(const Duration(seconds: 1));

      expect(exit, isA<ExitFailure<String, String>>());
      expect(released, isFalse);

      continueAcquisition.complete();
      await runtime.close();

      expect(released, isTrue);
    },
  );

  test('timeout cleanup failure does not replace its typed outcome', () async {
    final acquisitionStarted = Completer<void>();
    final continueAcquisition = Completer<void>();
    final diagnostics = <CleanupFailureDiagnostic>[];

    final runtime = await Module(
      const <Binding>[],
    ).start(cleanupFailureObserver: diagnostics.add);
    final running = runtime.runExit(
      Effect<String, String>.result((use) async {
        final resource = await use.acquire(
          Effect<Resource, String>.result((_) async {
            acquisitionStarted.complete();
            await continueAcquisition.future;
            return const Resource('late');
          }),
          release: (_, _) => throw const CleanupError(),
        );

        return resource.name;
      }).timeout(Duration.zero, onTimeout: () => 'timeout'),
    );

    await acquisitionStarted.future;
    final exit = await running;
    expect(exit, isA<ExitFailure<String, String>>());

    continueAcquisition.complete();
    await expectLater(runtime.close(), throwsA(isA<ScopeReleaseException>()));

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.outcome, same(exit));
  });

  test('concurrent Runtime.close calls share the active shutdown', () async {
    final started = Completer<void>();
    final continueExecution = Completer<void>();
    final runtime = await Module(const <Binding>[]).start();

    final running = runtime.run(
      Effect<Unit, Never>.result((use) async {
        started.complete();
        await continueExecution.future;
        return unit;
      }),
    );

    await started.future;
    final firstClose = runtime.close();
    final secondClose = runtime.close();

    expect(identical(firstClose, secondClose), isTrue);

    continueExecution.complete();
    await running;
    await firstClose;
  });

  test('EffectLocal values are inherited and locally overridden', () async {
    const requestId = EffectLocal<String>('default', name: 'requestId');

    final effect = Effect<String, Never>.result((use) async {
      return use.local(requestId);
    });

    final module = Module(const <Binding>[]);

    final defaultResult = await module.run(effect);
    final localResult = await module.run(
      effect.withLocal(requestId, 'request-123'),
    );

    expect(defaultResult.getOrNull(), 'default');
    expect(localResult.getOrNull(), 'request-123');
  });

  test('Effect.provide overrides one service only for that Effect', () async {
    final module = Module([.instance<String>('live')]);

    final effect = Effect<String, Never>.result((use) async {
      return use<String>();
    });

    final liveResult = await module.run(effect);
    final testResult = await module.run(effect.provide<String>('test'));

    expect(liveResult.getOrNull(), 'live');
    expect(testResult.getOrNull(), 'test');
  });
}
