import 'package:better_effect_flutter/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'registry.dart';

final class _CommandFailure implements Exception {
  const _CommandFailure(this.message);

  final String message;
}

final class _CommandResource {
  const _CommandResource(this.id);

  final int id;
}

void registerFlutterCommandScenarios() {
  conformanceTest('COMMAND-01', () async {
    var mode = 0;
    final runtime = await Module(const <Binding>[]).start();
    final commands = EffectCommands(runtime);
    final command = commands<int, _CommandFailure>(() {
      return switch (mode) {
        0 => Effect<int, _CommandFailure>.succeed(7),
        1 => Effect<int, _CommandFailure>.fail(const _CommandFailure('typed')),
        _ => Effect<int, _CommandFailure>.sync(
          () => throw StateError('defect'),
        ),
      };
    });

    expect(command.value, isA<EffectCommandIdle<int, _CommandFailure>>());
    expect(await command.execute(), isExitSuccess<int, _CommandFailure>(7));
    expect(command.value, isA<EffectCommandSuccess<int, _CommandFailure>>());

    mode = 1;
    expect(await command.execute(), isExitFailure<int, _CommandFailure>());
    expect(command.value, isA<EffectCommandFailure<int, _CommandFailure>>());

    mode = 2;
    expect(await command.execute(), isExitDefect<int, _CommandFailure>());
    expect(command.value, isA<EffectCommandDefect<int, _CommandFailure>>());

    command.dispose();
    await runtime.close();
  });

  conformanceTest('COMMAND-02', () async {
    final firstGate = TestGate<int>();
    final secondGate = TestGate<int>();
    final runtime = await Module(const <Binding>[]).start();
    final command = EffectCommands(runtime)
        .withInput<int, int, _CommandFailure>(
          (input) => Effect<int, _CommandFailure>.result(
            (_) => input == 1 ? firstGate.future : secondGate.future,
          ),
          policy: const CommandPolicy.latest(),
        );

    final first = command.execute(1);
    final second = command.execute(2);
    secondGate.complete(2);
    expect(expectExitSuccess(await second), 2);
    expect(command.data, 2);

    firstGate.complete(1);
    expect(expectExitSuccess(await first), 1);
    expect(command.data, 2);

    command.dispose();
    await runtime.close();
  });

  conformanceTest('COMMAND-03', () async {
    final gate = TestGate<int>();
    var starts = 0;
    final runtime = await Module(const <Binding>[]).start();
    final commands = EffectCommands(runtime);
    final command = commands<int, _CommandFailure>(
      () => Effect<int, _CommandFailure>.result((_) async {
        starts++;
        return gate.future;
      }),
      policy: const CommandPolicy.drop(),
    );

    final first = command.execute();
    final dropped = command.execute();
    expect(identical(first, dropped), isTrue);
    expect(starts, 1);

    gate.complete(1);
    expect(expectExitSuccess(await first), 1);
    command.dispose();
    await runtime.close();
  });

  conformanceTest('COMMAND-04', () async {
    final firstStarted = TestSignal();
    final runtime = await Module(const <Binding>[]).start();
    final command = EffectCommands(runtime)
        .withInput<int, int, _CommandFailure>(
          (input) => Effect<int, _CommandFailure>.result((use) async {
            if (input == 1) {
              firstStarted.signal();
              await use.cancellation.whenCancelled;
              use.cancellation.throwIfCancelled();
            }
            return input;
          }),
          policy: const CommandPolicy.latest(cancelPrevious: true),
        );

    final first = command.execute(1);
    await firstStarted.wait;
    final second = command.execute(2);

    expect(await first, isExitInterrupted<int, _CommandFailure>());
    expect(expectExitSuccess(await second), 2);
    expect(command.data, 2);

    command.dispose();
    await runtime.close();
  });

  conformanceTest('COMMAND-05', () async {
    final firstGate = TestSignal();
    final secondGate = TestSignal();
    final firstStarted = TestSignal();
    final secondStarted = TestSignal();
    final started = <int>[];
    final runtime = await Module(const <Binding>[]).start();
    final command = EffectCommands(runtime)
        .withInput<int, int, _CommandFailure>(
          (input) => Effect<int, _CommandFailure>.result((_) async {
            started.add(input);
            if (input == 1) {
              firstStarted.signal();
              await firstGate.wait;
            } else {
              secondStarted.signal();
              await secondGate.wait;
            }
            return input;
          }),
          policy: const CommandPolicy.queue(),
        );

    final first = command.execute(1);
    await firstStarted.wait;
    final second = command.execute(2);
    expect(started, <int>[1]);
    expect(command.queuedCount, 1);

    firstGate.signal();
    expect(expectExitSuccess(await first), 1);
    await secondStarted.wait;
    expect(started, <int>[1, 2]);

    secondGate.signal();
    expect(expectExitSuccess(await second), 2);
    command.dispose();
    await runtime.close();
  });

  conformanceTest('COMMAND-06', () async {
    final firstStarted = TestSignal();
    final continuePhysicalWork = TestSignal();
    final startedInputs = <int>[];
    final runtime = await Module(const <Binding>[]).start();
    final command = EffectCommands(runtime)
        .withInput<int, int, _CommandFailure>(
          (input) => Effect<int, _CommandFailure>.result((use) async {
            startedInputs.add(input);
            if (input == 1) {
              firstStarted.signal();
              await use.cancellation.whenCancelled;
              await continuePhysicalWork.wait;
            }
            return input;
          }),
          policy: const CommandPolicy.queue(),
        );

    final first = command.execute(1);
    await firstStarted.wait;
    final second = command.execute(2);
    final third = command.execute(3);

    expect(command.queuedCount, 2);
    expect(command.cancel(clearQueued: true), isTrue);
    expect(await first, isExitInterrupted<int, _CommandFailure>());
    expect(await second, isExitInterrupted<int, _CommandFailure>());
    expect(await third, isExitInterrupted<int, _CommandFailure>());
    expect(startedInputs, <int>[1]);

    continuePhysicalWork.signal();
    await runtime.close();
    expect(startedInputs, <int>[1]);
    command.dispose();
  });

  conformanceTest('COMMAND-07', () async {
    final runtime = await Module(const <Binding>[]).start();
    final commands = EffectCommands(runtime);
    final drop = commands<int, _CommandFailure>(
      () => Effect<int, _CommandFailure>.succeed(1),
      concurrency: EffectCommandConcurrency.drop,
    );
    final latest = commands<int, _CommandFailure>(
      () => Effect<int, _CommandFailure>.succeed(1),
      concurrency: EffectCommandConcurrency.latest,
    );
    final queue = commands<int, _CommandFailure>(
      () => Effect<int, _CommandFailure>.succeed(1),
      concurrency: EffectCommandConcurrency.queue,
    );

    expect(drop.policy.kind, CommandPolicyKind.drop);
    expect(latest.policy.kind, CommandPolicyKind.latest);
    expect(latest.policy.cancelPrevious, isFalse);
    expect(queue.policy.kind, CommandPolicyKind.queue);
    expect(queue.policy.trigger.isImmediate, isTrue);

    drop.dispose();
    latest.dispose();
    queue.dispose();
    await runtime.close();
  });

  conformanceWidgetTest('COMMAND-08', (tester) async {
    var deliveries = 0;
    final runtime = await Module(const <Binding>[]).start();
    final commands = EffectCommands(runtime);
    final command = commands<int, _CommandFailure>(
      () => Effect<int, _CommandFailure>.succeed(1),
    );

    Widget tree() {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: EffectCommandListener<int, _CommandFailure>(
          command: command,
          onSuccess: (_, _) {
            deliveries++;
          },
          child: const SizedBox(),
        ),
      );
    }

    await tester.pumpWidget(tree());
    await command.execute();
    await tester.pump();
    await tester.pump();
    expect(deliveries, 1);

    await tester.pumpWidget(tree());
    await tester.pump();
    expect(deliveries, 1);

    command.dispose();
    await runtime.close();
  });

  conformanceTest('COMMAND-09', () async {
    final started = TestSignal();
    final cancellationObserved = TestSignal();
    final continuePhysicalWork = TestSignal();
    var releases = 0;
    final runtime = await Module(const <Binding>[]).start();
    final commands = EffectCommands(runtime);
    final command = commands<int, _CommandFailure>(
      () => Effect<int, _CommandFailure>.result((use) async {
        await use.acquire(
          Effect<_CommandResource, _CommandFailure>.succeed(
            const _CommandResource(1),
          ),
          release: (_, _) {
            releases++;
          },
        );
        started.signal();
        await use.cancellation.whenCancelled;
        cancellationObserved.signal();
        await continuePhysicalWork.wait;
        return 42;
      }),
    );

    final running = command.execute();
    await started.wait;
    command.dispose();

    expect(await running, isExitInterrupted<int, _CommandFailure>());
    await cancellationObserved.wait;
    expect(releases, 0);

    final closing = runtime.close();
    expect(releases, 0);
    continuePhysicalWork.signal();
    await closing;
    expect(releases, 1);
  });

  conformanceTest('COMMAND-10', () async {
    final clock = ManualEffectClock();
    final runtime = await Module([.instance<EffectClock>(clock)]).start();
    final command = EffectCommands(runtime)
        .withInput<int, int, _CommandFailure>(
          (input) => Effect<int, _CommandFailure>.succeed(input),
          policy: const CommandPolicy.latest(
            trigger: TriggerPolicy.debounce(Duration(seconds: 1)),
          ),
        );

    final first = command.execute(1);
    await Future<void>.value();
    expect(clock.pendingSleepCount, 1);

    final second = command.execute(2);
    expect(await first, isExitInterrupted<int, _CommandFailure>());
    expect(command.triggerPendingCount, 1);

    await clock.advance(const Duration(seconds: 1));
    expect(expectExitSuccess(await second), 2);
    expect(command.data, 2);
    expect(clock.pendingSleepCount, 0);

    command.dispose();
    await runtime.close();
  });
}
