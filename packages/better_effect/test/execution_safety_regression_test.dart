import 'dart:async';

import 'package:better_effect/better_effect.dart';
import 'package:test/test.dart';

final class RegressionFailure implements Exception {
  const RegressionFailure(this.message);

  final String message;
}

final class RegressionCleanupError implements Exception {
  const RegressionCleanupError(this.label);

  final String label;

  @override
  String toString() => 'RegressionCleanupError($label)';
}

final class RegressionResource {
  const RegressionResource(this.id);

  final int id;
}

void main() {
  group('v0.2 execution safety — Scope races', () {
    test(
      'acquisition versus close releases every late resource exactly once',
      () async {
        for (var iteration = 0; iteration < 16; iteration++) {
          final scope = Scope.make();
          final acquisitionStarted = Completer<void>();
          final continueAcquisition = Completer<void>();
          final outcome = ExitInterrupted<Object, Object>();
          Exit<Object, Object>? releaseOutcome;
          var releases = 0;

          final acquisition = scope.acquire(
            () async {
              acquisitionStarted.complete();
              await continueAcquisition.future;
              return RegressionResource(iteration);
            },
            (_, exit) {
              releases++;
              releaseOutcome = exit;
            },
          );

          await acquisitionStarted.future;
          final closing = scope.close(outcome);
          continueAcquisition.complete();

          await expectLater(
            acquisition,
            throwsA(isA<ScopeClosedException>()),
            reason: 'iteration $iteration must reject late registration',
          );
          await closing;

          expect(releases, 1, reason: 'iteration $iteration leaked or doubled');
          expect(releaseOutcome, same(outcome));
        }
      },
    );

    test(
      'child and finalizer failures preserve deterministic cleanup order',
      () async {
        final root = Scope.make();
        final firstChild = root.fork();
        final secondChild = root.fork();

        root.addFinalizer(
          (_) => throw const RegressionCleanupError('root:first'),
        );
        root.addFinalizer(
          (_) => throw const RegressionCleanupError('root:second'),
        );
        firstChild.addFinalizer(
          (_) => throw const RegressionCleanupError('child:first'),
        );
        secondChild.addFinalizer(
          (_) => throw const RegressionCleanupError('child:second'),
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
              .map((item) => (item.error as RegressionCleanupError).label)
              .toList(),
          <String>['child:second', 'child:first', 'root:second', 'root:first'],
        );
      },
    );
  });

  group('v0.2 execution safety — Runtime ownership', () {
    test(
      'timeout keeps every late acquisition owned until physical completion',
      () async {
        for (var iteration = 0; iteration < 8; iteration++) {
          final acquisitionStarted = Completer<void>();
          final continueAcquisition = Completer<void>();
          var releases = 0;
          final runtime = await Module(const <Binding>[]).start();

          final running = runtime.runExit(
            Effect<int, RegressionFailure>.result((use) async {
              final resource = await use.acquire(
                Effect<RegressionResource, RegressionFailure>.result((_) async {
                  acquisitionStarted.complete();
                  await continueAcquisition.future;
                  return RegressionResource(iteration);
                }),
                release: (_, _) {
                  releases++;
                },
              );

              return resource.id;
            }).timeout(
              Duration.zero,
              onTimeout: () => RegressionFailure('timeout:$iteration'),
            ),
          );

          await acquisitionStarted.future;
          final exit = await running;

          expect(exit, isA<ExitFailure<int, RegressionFailure>>());
          expect(
            (exit as ExitFailure<int, RegressionFailure>).error.message,
            'timeout:$iteration',
          );
          expect(releases, 0);

          continueAcquisition.complete();
          await runtime.close();

          expect(releases, 1, reason: 'iteration $iteration leaked a resource');
        }
      },
    );

    test(
      'shutdown signals cancellation but still waits for non-cooperative work',
      () async {
        final executionStarted = Completer<void>();
        final cancellationObserved = Completer<Object?>();
        final continuePhysicalWork = Completer<void>();
        var runtimeReleases = 0;

        final runtime = await Module([
          .resource<RegressionResource>(
            acquire: (_) async => const RegressionResource(1),
            release: (_, _) {
              runtimeReleases++;
            },
          ),
        ]).start();
        final execution = runtime.execute(
          Effect<int, Never>.result((use) async {
            executionStarted.complete();
            await use.cancellation.whenCancelled;
            cancellationObserved.complete(use.cancellation.reason);
            await continuePhysicalWork.future;
            return 42;
          }),
          label: 'non-cooperative-after-signal',
        );

        await executionStarted.future;
        final closing = runtime.close(
          gracePeriod: Duration.zero,
          interruptAfterGracePeriod: true,
        );

        expect(await cancellationObserved.future, 'runtime-shutdown');
        expect(runtime.state, RuntimeState.closing);
        expect(execution.isRunning, isTrue);
        expect(runtimeReleases, 0);

        continuePhysicalWork.complete();

        expect(await execution.exit, isA<ExitSuccess<int, Never>>());
        await closing;

        expect(execution.isRunning, isFalse);
        expect(runtimeReleases, 1);
        expect(runtime.state, RuntimeState.closed);
      },
    );

    test(
      'completion-first and close-first boundaries remain stable when repeated',
      () async {
        for (var iteration = 0; iteration < 12; iteration++) {
          final executionStarted = Completer<void>();
          final continueExecution = Completer<void>();
          final events = <String>[];
          final runtime = await Module([
            .resource<RegressionResource>(
              acquire: (_) async => RegressionResource(iteration),
              release: (_, _) {
                events.add('release:runtime');
              },
            ),
          ]).start();
          final execution = runtime.execute(
            Effect<int, Never>.result((use) async {
              await use.acquire(
                Effect<RegressionResource, Never>.succeed(
                  RegressionResource(iteration),
                ),
                release: (_, _) {
                  events.add('release:execution');
                },
              );
              executionStarted.complete();
              await continueExecution.future;
              return iteration;
            }),
          );

          await executionStarted.future;

          late Future<void> firstClose;
          late Future<void> secondClose;
          if (iteration.isEven) {
            firstClose = runtime.close();
            secondClose = runtime.close();
            expect(identical(firstClose, secondClose), isTrue);
            expect(runtime.state, RuntimeState.closing);
            expect(events, isEmpty);
            continueExecution.complete();
          } else {
            continueExecution.complete();
            expect(await execution.exit, isA<ExitSuccess<int, Never>>());
            firstClose = runtime.close();
            secondClose = runtime.close();
            expect(identical(firstClose, secondClose), isTrue);
          }

          expect(await execution.exit, isA<ExitSuccess<int, Never>>());
          await firstClose;
          await secondClose;

          expect(events, <String>['release:execution', 'release:runtime']);
          expect(runtime.state, RuntimeState.closed);
        }
      },
    );

    test(
      'the first logical outcome stays authoritative across bounded races',
      () async {
        final runtime = await Module(const <Binding>[]).start();
        var releases = 0;

        for (var iteration = 0; iteration < 16; iteration++) {
          final executionStarted = Completer<void>();
          final continueExecution = Completer<void>();
          final execution = runtime.execute(
            Effect<int, Never>.result((use) async {
              await use.acquire(
                Effect<RegressionResource, Never>.succeed(
                  RegressionResource(iteration),
                ),
                release: (_, _) {
                  releases++;
                },
              );
              executionStarted.complete();
              await continueExecution.future;
              return iteration;
            }),
            label: 'authority:$iteration',
          );

          await executionStarted.future;

          if (iteration.isEven) {
            expect(execution.interrupt(reason: 'cancel:$iteration'), isTrue);
            expect(await execution.exit, isA<ExitInterrupted<int, Never>>());
            continueExecution.complete();
          } else {
            continueExecution.complete();
            final exit = await execution.exit;
            expect(exit, isA<ExitSuccess<int, Never>>());
            expect((exit as ExitSuccess<int, Never>).value, iteration);

            execution.interrupt(reason: 'after-success');
            expect(await execution.exit, same(exit));
          }
        }

        await runtime.close();
        expect(releases, 16);
      },
    );
  });

  group('v0.2 execution safety — cleanup precedence', () {
    test(
      'interruption survives cleanup failure and an observer that throws',
      () async {
        final diagnostics = <CleanupFailureDiagnostic>[];
        final executionStarted = Completer<void>();
        final continueExecution = Completer<void>();
        final runtime = await Module(const <Binding>[]).start(
          cleanupFailureObserver: (diagnostic) {
            diagnostics.add(diagnostic);
            throw StateError('observer must remain best-effort');
          },
        );
        final execution = runtime.execute(
          Effect<int, Never>.result((use) async {
            await use.acquire(
              Effect<RegressionResource, Never>.succeed(
                const RegressionResource(1),
              ),
              release: (_, _) =>
                  throw const RegressionCleanupError('interrupted-release'),
            );
            executionStarted.complete();
            await continueExecution.future;
            return 42;
          }),
          label: 'interrupted-cleanup',
        );

        await executionStarted.future;
        expect(execution.interrupt(reason: 'test-interruption'), isTrue);
        final exit = await execution.exit;

        expect(exit, isA<ExitInterrupted<int, Never>>());
        expect(execution.isRunning, isTrue);

        continueExecution.complete();
        await expectLater(
          runtime.close(),
          throwsA(isA<ScopeReleaseException>()),
        );

        expect(diagnostics, hasLength(1));
        expect(diagnostics.single.outcome, same(exit));
        expect(diagnostics.single.executionLabel, 'interrupted-cleanup');
        expect(diagnostics.single.error.failures, hasLength(1));
        expect(
          diagnostics.single.error.failures.single.error,
          isA<RegressionCleanupError>(),
        );
        expect(runtime.state, RuntimeState.closed);
      },
    );
  });
}
