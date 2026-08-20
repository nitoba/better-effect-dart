import 'dart:async';

import 'package:better_effect_flutter/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final class PolicyFailure implements Exception {
  const PolicyFailure();
}

void main() {
  late ManualEffectClock clock;
  late Runtime runtime;
  late EffectCommands commands;

  setUp(() async {
    clock = ManualEffectClock();
    runtime = await Module([.instance<EffectClock>(clock)]).start();
    commands = EffectCommands(runtime);
  });

  tearDown(() async {
    if (runtime.state != RuntimeState.closed) {
      await runtime.close(
        gracePeriod: Duration.zero,
        interruptAfterGracePeriod: true,
      );
    }
  });

  group('CommandPolicy compatibility', () {
    test('legacy enum values translate exactly to immutable policies', () {
      final drop = commands<int, PolicyFailure>(
        () => Effect<int, PolicyFailure>.succeed(1),
        concurrency: EffectCommandConcurrency.drop,
      );
      final latest = commands<int, PolicyFailure>(
        () => Effect<int, PolicyFailure>.succeed(1),
        concurrency: EffectCommandConcurrency.latest,
      );
      final queue = commands<int, PolicyFailure>(
        () => Effect<int, PolicyFailure>.succeed(1),
        concurrency: EffectCommandConcurrency.queue,
      );
      addTearDown(drop.dispose);
      addTearDown(latest.dispose);
      addTearDown(queue.dispose);

      expect(drop.policy.kind, CommandPolicyKind.drop);
      expect(latest.policy.kind, CommandPolicyKind.latest);
      expect(latest.policy.cancelPrevious, isFalse);
      expect(queue.policy.kind, CommandPolicyKind.queue);
      expect(queue.policy.maxPending, isNull);
      expect(queue.policy.trigger.isImmediate, isTrue);
    });

    test('simple command creation remains drop by default', () {
      final command = commands<int, PolicyFailure>(
        () => Effect<int, PolicyFailure>.succeed(1),
      );
      addTearDown(command.dispose);

      expect(command.policy.kind, CommandPolicyKind.drop);
      expect(command.policy.trigger.isImmediate, isTrue);
    });

    test('policy and compatibility enum cannot be supplied together', () {
      expect(
        () => commands<int, PolicyFailure>(
          () => Effect<int, PolicyFailure>.succeed(1),
          policy: const CommandPolicy.latest(),
          concurrency: EffectCommandConcurrency.latest,
        ),
        throwsArgumentError,
      );
    });

    test('timed triggers require typed input Commands', () {
      expect(
        () => commands<int, PolicyFailure>(
          () => Effect<int, PolicyFailure>.succeed(1),
          policy: const CommandPolicy.drop(
            trigger: TriggerPolicy.debounce(Duration(seconds: 1)),
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('latest', () {
    test('cancelPrevious reaches the managed interruption signal', () async {
      final firstStarted = Completer<void>();
      final firstCancelled = Completer<Object?>();
      final continueFirst = Completer<void>();
      final command = commands.withInput<int, int, PolicyFailure>(
        (input) => Effect<int, PolicyFailure>.result((use) async {
          if (input == 1) {
            firstStarted.complete();
            await use.cancellation.whenCancelled;
            firstCancelled.complete(use.cancellation.reason);
            await continueFirst.future;
          }
          return input;
        }),
        policy: const CommandPolicy.latest(cancelPrevious: true),
      );
      addTearDown(command.dispose);

      final first = command.execute(1);
      await firstStarted.future;
      final second = command.execute(2);

      expect(await first, isA<ExitInterrupted<int, PolicyFailure>>());
      expect(await firstCancelled.future, 'command-policy-latest-superseded');
      expect(expectExitSuccess(await second), 2);
      expect(command.data, 2);

      continueFirst.complete();
    });

    test('default latest preserves independent caller outcomes', () async {
      final firstGate = Completer<int>();
      final secondGate = Completer<int>();
      final command = commands.withInput<int, int, PolicyFailure>(
        (input) => Effect<int, PolicyFailure>.result(
          (_) => input == 1 ? firstGate.future : secondGate.future,
        ),
        policy: const CommandPolicy.latest(),
      );
      addTearDown(command.dispose);

      final first = command.execute(1);
      final second = command.execute(2);
      secondGate.complete(2);
      expect(expectExitSuccess(await second), 2);

      firstGate.complete(1);
      expect(expectExitSuccess(await first), 1);
      expect(command.data, 2);
    });
  });

  group('debounce', () {
    test(
      'trailing debounce replaces the pending caller deterministically',
      () async {
        final started = <int>[];
        final probe = EffectCommandPolicyProbe();
        final command = commands.withInput<int, int, PolicyFailure>(
          (input) => Effect<int, PolicyFailure>.sync(() {
            started.add(input);
            return input;
          }),
          policy: const CommandPolicy.latest(
            trigger: TriggerPolicy.debounce(Duration(seconds: 1)),
          ),
          policyObserver: probe.call,
        );
        addTearDown(command.dispose);

        final first = command.execute(1);
        await Future<void>.value();
        expect(started, isEmpty);
        expect(clock.pendingSleepCount, 1);

        final second = command.execute(2);
        expect(await first, isA<ExitInterrupted<int, PolicyFailure>>());
        expect(command.lastInputOrNull, 2);
        expect(command.triggerPendingCount, 1);

        await clock.advance(const Duration(milliseconds: 999));
        expect(started, isEmpty);
        await clock.advance(const Duration(milliseconds: 1));
        expect(expectExitSuccess(await second), 2);
        expect(started, <int>[2]);
        expect(command.data, 2);

        expect(
          probe.whereDecision(CommandPolicyDecision.replaced),
          hasLength(1),
        );
        expect(
          probe.whereDecision(CommandPolicyDecision.triggerFired),
          hasLength(1),
        );
      },
    );

    test(
      'leading and trailing debounce executes both accepted edges',
      () async {
        final started = <int>[];
        final command = commands.withInput<int, int, PolicyFailure>(
          (input) => Effect<int, PolicyFailure>.sync(() {
            started.add(input);
            return input;
          }),
          policy: const CommandPolicy.latest(
            trigger: TriggerPolicy.debounce(
              Duration(seconds: 1),
              leading: true,
              trailing: true,
            ),
          ),
        );
        addTearDown(command.dispose);

        expect(expectExitSuccess(await command.execute(1)), 1);
        final trailing = command.execute(2);
        expect(started, <int>[1]);

        await clock.advance(const Duration(seconds: 1));
        expect(expectExitSuccess(await trailing), 2);
        expect(started, <int>[1, 2]);
      },
    );
  });

  group('throttle', () {
    test(
      'trailing throttle keeps only the latest pending invocation',
      () async {
        final started = <int>[];
        final command = commands.withInput<int, int, PolicyFailure>(
          (input) => Effect<int, PolicyFailure>.sync(() {
            started.add(input);
            return input;
          }),
          policy: const CommandPolicy.latest(
            trigger: TriggerPolicy.throttle(
              Duration(seconds: 1),
              leading: true,
              trailing: true,
            ),
          ),
        );
        addTearDown(command.dispose);

        expect(expectExitSuccess(await command.execute(1)), 1);
        final second = command.execute(2);
        final third = command.execute(3);

        expect(await second, isA<ExitInterrupted<int, PolicyFailure>>());
        expect(started, <int>[1]);

        await clock.advance(const Duration(seconds: 1));
        expect(expectExitSuccess(await third), 3);
        expect(started, <int>[1, 3]);

        await clock.advance(const Duration(seconds: 1));
        expect(command.triggerPendingCount, 0);
      },
    );

    test(
      'leading-only throttle rejects calls without replacing retry input',
      () async {
        final started = <int>[];
        final command = commands.withInput<int, int, PolicyFailure>(
          (input) => Effect<int, PolicyFailure>.sync(() {
            started.add(input);
            return input;
          }),
          policy: const CommandPolicy.latest(
            trigger: TriggerPolicy.throttle(Duration(seconds: 1)),
          ),
        );
        addTearDown(command.dispose);

        expect(expectExitSuccess(await command.execute(1)), 1);
        expect(
          await command.execute(2),
          isA<ExitInterrupted<int, PolicyFailure>>(),
        );
        expect(command.lastInputOrNull, 1);

        await clock.advance(const Duration(seconds: 1));
        expect(expectExitSuccess(await command.retry()), 1);
        expect(started, <int>[1, 1]);
      },
    );
  });

  group('bounded queue', () {
    Future<void> verifyNewestOverflow(QueueOverflow overflow) async {
      final firstGate = Completer<void>();
      final secondGate = Completer<void>();
      final started = <int>[];
      final probe = EffectCommandPolicyProbe();
      final command = commands.withInput<int, int, PolicyFailure>(
        (input) => Effect<int, PolicyFailure>.result((_) async {
          started.add(input);
          if (input == 1) await firstGate.future;
          if (input == 2) await secondGate.future;
          return input;
        }),
        policy: CommandPolicy.queue(maxPending: 1, overflow: overflow),
        policyObserver: probe.call,
      );
      addTearDown(command.dispose);

      final first = command.execute(1);
      final second = command.execute(2);
      final third = command.execute(3);
      await Future<void>.value();

      expect(started, <int>[1]);
      expect(command.queuedCount, 1);
      expect(await third, isA<ExitInterrupted<int, PolicyFailure>>());
      expect(command.lastInputOrNull, 2);

      firstGate.complete();
      expect(expectExitSuccess(await first), 1);
      await Future<void>.value();
      expect(started, <int>[1, 2]);
      secondGate.complete();
      expect(expectExitSuccess(await second), 2);

      final expectedReason = overflow == QueueOverflow.rejectNewest
          ? CommandPolicyReason.queueRejectedNewest
          : CommandPolicyReason.queueDroppedNewest;
      expect(
        probe.events.any((event) => event.reason == expectedReason),
        isTrue,
      );
    }

    test(
      'rejectNewest has a deterministic interrupted caller outcome',
      () async {
        await verifyNewestOverflow(QueueOverflow.rejectNewest);
      },
    );

    test('dropNewest has a deterministic interrupted caller outcome', () async {
      await verifyNewestOverflow(QueueOverflow.dropNewest);
    });

    test(
      'dropOldest interrupts the oldest queued caller and admits newest',
      () async {
        final firstGate = Completer<void>();
        final thirdGate = Completer<void>();
        final started = <int>[];
        final command = commands.withInput<int, int, PolicyFailure>(
          (input) => Effect<int, PolicyFailure>.result((_) async {
            started.add(input);
            if (input == 1) await firstGate.future;
            if (input == 3) await thirdGate.future;
            return input;
          }),
          policy: const CommandPolicy.queue(
            maxPending: 1,
            overflow: QueueOverflow.dropOldest,
          ),
        );
        addTearDown(command.dispose);

        final first = command.execute(1);
        final second = command.execute(2);
        final third = command.execute(3);
        await Future<void>.value();

        expect(await second, isA<ExitInterrupted<int, PolicyFailure>>());
        expect(command.queuedCount, 1);
        expect(command.lastInputOrNull, 3);

        firstGate.complete();
        expect(expectExitSuccess(await first), 1);
        await Future<void>.value();
        expect(started, <int>[1, 3]);
        thirdGate.complete();
        expect(expectExitSuccess(await third), 3);
      },
    );
  });

  group('timer lifecycle and diagnostics', () {
    test('cancel clears a trailing trigger and its caller', () async {
      final command = commands.withInput<int, int, PolicyFailure>(
        (input) => Effect<int, PolicyFailure>.succeed(input),
        policy: const CommandPolicy.latest(
          trigger: TriggerPolicy.debounce(Duration(seconds: 1)),
        ),
      );
      addTearDown(command.dispose);

      final pending = command.execute(1);
      await Future<void>.value();
      expect(clock.pendingSleepCount, 1);
      expect(command.cancel(), isTrue);
      expect(await pending, isA<ExitInterrupted<int, PolicyFailure>>());
      await Future<void>.value();
      expect(clock.pendingSleepCount, 0);
      expect(command.pendingCount, 0);
    });

    test('Runtime shutdown interrupts a pending trigger caller', () async {
      final command = commands.withInput<int, int, PolicyFailure>(
        (input) => Effect<int, PolicyFailure>.succeed(input),
        policy: const CommandPolicy.latest(
          trigger: TriggerPolicy.debounce(Duration(seconds: 1)),
        ),
      );
      addTearDown(command.dispose);

      final pending = command.execute(1);
      await Future<void>.value();
      await runtime.close(
        gracePeriod: Duration.zero,
        interruptAfterGracePeriod: true,
      );

      expect(await pending, isA<ExitInterrupted<int, PolicyFailure>>());
      expect(command.pendingCount, 0);
    });

    test(
      'policy observers receive decisions without changing execution',
      () async {
        final probe = EffectCommandPolicyProbe();
        final previousHandler = FlutterError.onError;
        final observerErrors = <FlutterErrorDetails>[];
        FlutterError.onError = observerErrors.add;
        addTearDown(() => FlutterError.onError = previousHandler);

        final observedCommands = EffectCommands(
          runtime,
          policyObserver: (event) {
            probe.call(event);
            throw StateError('observer failed');
          },
        );
        final command = observedCommands<int, PolicyFailure>(
          () => Effect<int, PolicyFailure>.succeed(42),
          debugLabel: 'policy-observed',
        );
        addTearDown(command.dispose);

        expect(expectExitSuccess(await command.execute()), 42);
        expect(command.data, 42);
        expect(
          probe.whereDecision(CommandPolicyDecision.started),
          hasLength(1),
        );
        expect(observerErrors, isNotEmpty);
        expect(probe.events.single.debugLabel, 'policy-observed');
      },
    );

    test('missing EffectClock is surfaced as a Command defect', () async {
      final noClockRuntime = await Module(const <Binding>[]).start();
      addTearDown(noClockRuntime.close);
      final noClockCommands = EffectCommands(noClockRuntime);
      final command = noClockCommands.withInput<int, int, PolicyFailure>(
        (input) => Effect<int, PolicyFailure>.succeed(input),
        policy: const CommandPolicy.latest(
          trigger: TriggerPolicy.debounce(Duration(seconds: 1)),
        ),
      );
      addTearDown(command.dispose);

      final exit = await command.execute(1);
      expect(exit, isA<ExitDefect<int, PolicyFailure>>());
      expect(command.value, isA<EffectCommandDefect<int, PolicyFailure>>());
    });
  });
}
