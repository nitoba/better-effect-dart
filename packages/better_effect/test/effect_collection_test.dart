import 'dart:async';

import 'package:better_effect/testing.dart';
import 'package:test/test.dart';

final class BatchFailure implements Exception {
  const BatchFailure(this.index);

  final int index;

  @override
  String toString() => 'BatchFailure($index)';
}

final class BatchResource {
  const BatchResource(this.index);

  final int index;
}

void main() {
  group('Effect collection composition', () {
    test('is lazy and returns an unmodifiable ordered List', () async {
      var iterations = 0;
      var mappings = 0;

      Iterable<int> inputs() sync* {
        iterations++;
        yield 1;
        yield 2;
        yield 3;
      }

      final effect = Effect.forEach(
        inputs(),
        (value) => Effect<int, BatchFailure>.sync(() {
          mappings++;
          return value * 10;
        }),
      );

      expect(iterations, 0);
      expect(mappings, 0);

      final exit = await Module(const <Binding>[]).runExit(effect);
      final values = expectExitSuccess(exit);

      expect(iterations, 1);
      expect(mappings, 3);
      expect(values, <int>[10, 20, 30]);
      expect(() => values.add(40), throwsUnsupportedError);
    });

    test(
      'supports empty, singleton, all, and explicit unbounded input',
      () async {
        var emptyMappings = 0;
        final empty = Effect.forEach(const <int>[], (value) {
          emptyMappings++;
          return Effect<int, BatchFailure>.succeed(value);
        });
        final singleton = Effect.forEach(const <int>[
          7,
        ], (value) => Effect<int, BatchFailure>.succeed(value * 2));
        final all = Effect.all<int, BatchFailure>(<Effect<int, BatchFailure>>[
          Effect<int, BatchFailure>.succeed(1),
          Effect<int, BatchFailure>.succeed(2),
        ]);
        final unbounded = Effect.allUnbounded<int, BatchFailure>(
          <Effect<int, BatchFailure>>[
            Effect<int, BatchFailure>.succeed(3),
            Effect<int, BatchFailure>.succeed(4),
          ],
        );
        final module = Module(const <Binding>[]);

        expect(expectExitSuccess(await module.runExit(empty)), isEmpty);
        expect(emptyMappings, 0);
        expect(expectExitSuccess(await module.runExit(singleton)), <int>[14]);
        expect(expectExitSuccess(await module.runExit(all)), <int>[1, 2]);
        expect(expectExitSuccess(await module.runExit(unbounded)), <int>[3, 4]);
      },
    );

    test('preserves input order after out-of-order completion', () async {
      final harness = await TestRuntime.start(
        Module(const <Binding>[]),
        registerCleanup: (cleanup) => addTearDown(cleanup),
      );
      final gates = List<TestGate<int>>.generate(3, (_) => TestGate<int>());
      final allStarted = Completer<void>.sync();
      var started = 0;
      final effect = Effect.forEach(
        const <int>[0, 1, 2],
        (index) => Effect<int, BatchFailure>.result((_) async {
          started++;
          if (started == gates.length) allStarted.complete();
          return gates[index].future;
        }),
        concurrency: 3,
      );

      final execution = harness.execute(effect);
      await allStarted.future;

      gates[2].complete(30);
      gates[0].complete(10);
      gates[1].complete(20);

      expect(expectExitSuccess(await execution.exit), <int>[10, 20, 30]);
    });

    test('never exceeds the configured active worker count', () async {
      final harness = await TestRuntime.start(
        Module(const <Binding>[]),
        registerCleanup: (cleanup) => addTearDown(cleanup),
      );
      final gates = List<TestSignal>.generate(12, (_) => TestSignal());
      final firstWindowStarted = Completer<void>.sync();
      var active = 0;
      var maximumActive = 0;
      var started = 0;

      final effect = Effect.forEach(
        List<int>.generate(gates.length, (index) => index),
        (index) => Effect<int, BatchFailure>.result((_) async {
          active++;
          started++;
          if (active > maximumActive) maximumActive = active;
          if (started == 3) firstWindowStarted.complete();

          await gates[index].wait;
          active--;
          return index;
        }),
        concurrency: 3,
      );

      final execution = harness.execute(effect);
      await firstWindowStarted.future;

      expect(maximumActive, 3);
      for (final gate in gates) {
        gate.signal();
      }

      final values = expectExitSuccess(await execution.exit);
      expect(values, List<int>.generate(gates.length, (index) => index));
      expect(started, gates.length);
      expect(maximumActive, 3);
    });

    test(
      'stops FIFO scheduling after the first observed typed failure',
      () async {
        final harness = await TestRuntime.start(
          Module(const <Binding>[]),
          registerCleanup: (cleanup) => addTearDown(cleanup),
        );
        final gates = List<TestSignal>.generate(2, (_) => TestSignal());
        final firstWindowStarted = Completer<void>.sync();
        final failureReturned = TestSignal();
        final started = <int>[];

        final effect = Effect.forEach(
          const <int>[0, 1, 2, 3, 4],
          (index) => Effect<int, BatchFailure>.result((use) async {
            started.add(index);
            if (started.length == 2) firstWindowStarted.complete();
            await gates[index].wait;

            if (index == 1) {
              failureReturned.signal();
              use.fail(const BatchFailure(1));
            }
            return index;
          }),
          concurrency: 2,
        );

        final execution = harness.execute(effect);
        await firstWindowStarted.future;
        gates[1].signal();
        await failureReturned.wait;
        await Future<void>.delayed(Duration.zero);

        expect(started, <int>[0, 1]);
        gates[0].signal();

        expect(expectExitFailure(await execution.exit).index, 1);
        expect(started, <int>[0, 1]);
      },
    );

    test(
      'selects the lowest input index among started typed failures',
      () async {
        final harness = await TestRuntime.start(
          Module(const <Binding>[]),
          registerCleanup: (cleanup) => addTearDown(cleanup),
        );
        final gates = List<TestSignal>.generate(3, (_) => TestSignal());
        final allStarted = Completer<void>.sync();
        var started = 0;

        final effect = Effect.forEach(
          const <int>[0, 1, 2, 3],
          (index) => Effect<int, BatchFailure>.result((use) async {
            started++;
            if (started == 3) allStarted.complete();
            await gates[index].wait;

            if (index == 0 || index == 2) {
              use.fail(BatchFailure(index));
            }
            return index;
          }),
          concurrency: 3,
        );

        final execution = harness.execute(effect);
        await allStarted.future;

        gates[2].signal();
        await Future<void>.delayed(Duration.zero);
        gates[0].signal();
        gates[1].signal();

        expect(expectExitFailure(await execution.exit).index, 0);
        expect(started, 3);
      },
    );

    test('keeps defects outside the typed failure channel', () async {
      final harness = await TestRuntime.start(
        Module(const <Binding>[]),
        registerCleanup: (cleanup) => addTearDown(cleanup),
      );
      final gates = List<TestSignal>.generate(3, (_) => TestSignal());
      final allStarted = Completer<void>.sync();
      var started = 0;

      final effect = Effect.forEach(
        const <int>[0, 1, 2],
        (index) => Effect<int, BatchFailure>.result((_) async {
          started++;
          if (started == 3) allStarted.complete();
          await gates[index].wait;

          if (index == 0 || index == 2) {
            throw StateError('defect-$index');
          }
          return index;
        }),
        concurrency: 3,
      );

      final execution = harness.execute(effect);
      await allStarted.future;

      gates[2].signal();
      await Future<void>.delayed(Duration.zero);
      gates[0].signal();
      gates[1].signal();

      final defect = expectExitDefect(await execution.exit).defect;
      expect(defect, isA<StateError>());
      expect((defect as StateError).message, 'defect-0');
    });

    test(
      'starts no collection items after interruption was requested',
      () async {
        final harness = await TestRuntime.start(
          Module(const <Binding>[]),
          registerCleanup: (cleanup) => addTearDown(cleanup),
        );
        final entered = TestSignal();
        var mappings = 0;
        final ended = harness.observer.next<ExecutionEndEvent>(
          where: (event) => event.context.executionLabel == 'before-batch',
        );
        final effect = Effect<List<int>, BatchFailure>.result((use) async {
          entered.signal();
          await use.cancellation.whenCancelled;

          return use.unwrap(
            Effect.forEach(const <int>[0, 1, 2], (value) {
              mappings++;
              return Effect<int, BatchFailure>.succeed(value);
            }, concurrency: 2),
          );
        });

        final execution = harness.execute(effect, label: 'before-batch');
        await entered.wait;
        expect(execution.interrupt(reason: 'test-owner'), isTrue);
        expect(
          await execution.exit,
          isExitInterrupted<List<int>, BatchFailure>(),
        );
        await ended;
        await _waitForPhysicalCompletion(execution);

        expect(mappings, 0);
        expect(execution.isRunning, isFalse);
      },
    );

    test('interruption stops scheduling but drains started work', () async {
      final harness = await TestRuntime.start(
        Module(const <Binding>[]),
        registerCleanup: (cleanup) => addTearDown(cleanup),
      );
      final gates = List<TestSignal>.generate(2, (_) => TestSignal());
      final firstWindowStarted = Completer<void>.sync();
      final started = <int>[];
      final ended = harness.observer.next<ExecutionEndEvent>(
        where: (event) => event.context.executionLabel == 'mid-batch',
      );
      final effect = Effect.forEach(
        const <int>[0, 1, 2, 3],
        (index) => Effect<int, BatchFailure>.result((_) async {
          started.add(index);
          if (started.length == 2) firstWindowStarted.complete();
          await gates[index].wait;
          return index;
        }),
        concurrency: 2,
      );

      final execution = harness.execute(effect, label: 'mid-batch');
      await firstWindowStarted.future;
      expect(execution.interrupt(reason: 'test-owner'), isTrue);
      expect(
        await execution.exit,
        isExitInterrupted<List<int>, BatchFailure>(),
      );
      expect(execution.isRunning, isTrue);

      gates[0].signal();
      gates[1].signal();
      await ended;
      await _waitForPhysicalCompletion(execution);

      expect(started, <int>[0, 1]);
      expect(execution.isRunning, isFalse);
    });

    test(
      'worker resources stay owned until the enclosing execution closes',
      () async {
        final events = TestEventRecorder<String>();
        final effect = Effect.forEach(
          const <int>[0, 1, 2],
          (index) => Effect<int, BatchFailure>.result((use) async {
            final resource = await use.acquire(
              Effect<BatchResource, BatchFailure>.sync(() {
                events.record('acquire:$index');
                return BatchResource(index);
              }),
              release: (resource, _) {
                events.record('release:${resource.index}');
              },
            );
            events.record('use:${resource.index}');
            return resource.index;
          }),
        );

        final exit = await Module(const <Binding>[]).runExit(effect);

        expect(expectExitSuccess(exit), <int>[0, 1, 2]);
        events.expectEvents(const <String>[
          'acquire:0',
          'use:0',
          'acquire:1',
          'use:1',
          'acquire:2',
          'use:2',
          'release:2',
          'release:1',
          'release:0',
        ]);
      },
    );

    test('a timeout keeps started batch work physically owned', () async {
      final harness = await TestRuntime.start(
        Module(const <Binding>[]),
        registerCleanup: (cleanup) => addTearDown(cleanup),
      );
      final gates = List<TestSignal>.generate(2, (_) => TestSignal());
      final allStarted = Completer<void>.sync();
      var started = 0;
      final ended = harness.observer.next<ExecutionEndEvent>(
        where: (event) => event.context.executionLabel == 'timed-batch',
      );
      final batch = Effect.forEach(
        const <int>[0, 1],
        (index) => Effect<int, BatchFailure>.result((_) async {
          started++;
          if (started == 2) allStarted.complete();
          await gates[index].wait;
          return index;
        }),
        concurrency: 2,
      ).timeout(Duration.zero, onTimeout: () => const BatchFailure(-1));

      final execution = harness.execute(batch, label: 'timed-batch');
      await allStarted.future;
      expect(expectExitFailure(await execution.exit).index, -1);
      expect(execution.isRunning, isTrue);

      gates[0].signal();
      gates[1].signal();
      await ended;
      await _waitForPhysicalCompletion(execution);

      expect(execution.isRunning, isFalse);
    });

    test('rejects non-positive bounded concurrency', () {
      expect(
        () => Effect.forEach(
          const <int>[1],
          (value) => Effect<int, BatchFailure>.succeed(value),
          concurrency: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => Effect.all<int, BatchFailure>(<Effect<int, BatchFailure>>[
          Effect<int, BatchFailure>.succeed(1),
        ], concurrency: -1),
        throwsArgumentError,
      );
    });

    test('is stack-safe for large sequential inputs', () async {
      const size = 5000;
      final effect = Effect.forEach(
        List<int>.generate(size, (index) => index),
        (value) => Effect<int, Never>.succeed(value + 1),
      );

      final values = expectExitSuccess(
        await Module(const <Binding>[]).runExit(effect),
      );

      expect(values, hasLength(size));
      expect(values.first, 1);
      expect(values.last, size);
    });
  });
}

Future<void> _waitForPhysicalCompletion<A extends Object, E extends Object>(
  EffectExecution<A, E> execution,
) async {
  while (execution.isRunning) {
    await Future<void>.delayed(Duration.zero);
  }
}
