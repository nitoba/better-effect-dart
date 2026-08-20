import 'dart:async';

import 'package:better_effect/testing.dart';
import 'package:test/test.dart';

final class CollectionResourceFailure implements Exception {
  const CollectionResourceFailure();
}

final class CollectionResource {
  const CollectionResource(this.index);

  final int index;
}

void main() {
  test(
    'bounded workers release resources in reverse acquisition order',
    () async {
      final harness = await TestRuntime.start(
        Module(const <Binding>[]),
        registerCleanup: (cleanup) => addTearDown(cleanup),
      );
      final events = TestEventRecorder<String>();
      final gates = List<TestSignal>.generate(2, (_) => TestSignal());
      final allAcquired = Completer<void>.sync();
      final secondUsed = TestSignal();
      var acquired = 0;
      final ended = harness.observer.next<ExecutionEndEvent>(
        where: (event) => event.context.executionLabel == 'resource-batch',
      );

      final batch = Effect.forEach(
        const <int>[0, 1],
        (index) => Effect<int, CollectionResourceFailure>.result((use) async {
          final resource = await use.acquire(
            Effect<CollectionResource, CollectionResourceFailure>.sync(() {
              events.record('acquire:$index');
              acquired++;
              if (acquired == 2) allAcquired.complete();
              return CollectionResource(index);
            }),
            release: (resource, _) {
              events.record('release:${resource.index}');
            },
          );

          await gates[index].wait;
          events.record('use:${resource.index}');
          if (index == 1) secondUsed.signal();
          return resource.index;
        }),
        concurrency: 2,
      );

      final execution = harness.execute(batch, label: 'resource-batch');
      await allAcquired.future;

      gates[1].signal();
      await secondUsed.wait;
      gates[0].signal();

      expect(expectExitSuccess(await execution.exit), <int>[0, 1]);
      await ended;
      await _waitForPhysicalCompletion(execution);

      events.expectEvents(const <String>[
        'acquire:0',
        'acquire:1',
        'use:1',
        'use:0',
        'release:1',
        'release:0',
      ]);
    },
  );
}

Future<void> _waitForPhysicalCompletion<A extends Object, E extends Object>(
  EffectExecution<A, E> execution,
) async {
  while (execution.isRunning) {
    await Future<void>.delayed(Duration.zero);
  }
}
