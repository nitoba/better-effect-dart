import 'dart:async';

import 'package:better_effect/testing.dart';
import 'package:test/test.dart';

final class RetryFailure implements Exception {
  const RetryFailure(this.code);

  final int code;

  @override
  String toString() => 'RetryFailure($code)';
}

final class RetryResource {
  const RetryResource(this.attempt);

  final int attempt;
}

final class _SequenceRandom implements EffectRandom {
  _SequenceRandom(Iterable<double> values) : _values = List<double>.of(values);

  final List<double> _values;
  var calls = 0;

  @override
  double nextDouble() {
    if (calls >= _values.length) {
      throw StateError('No random value remains.');
    }
    return _values[calls++];
  }
}

final class _TwoAttemptPolicy implements RetryPolicy<RetryFailure> {
  const _TwoAttemptPolicy();

  @override
  Duration? nextDelay(RetryContext<RetryFailure> context) {
    return context.attempt < 2 ? Duration.zero : null;
  }
}

final class _NegativeDelayPolicy implements RetryPolicy<RetryFailure> {
  const _NegativeDelayPolicy();

  @override
  Duration? nextDelay(RetryContext<RetryFailure> context) {
    return const Duration(microseconds: -1);
  }
}

void main() {
  group('Effect.retry', () {
    test('is lazy and an immediate success runs once', () async {
      var attempts = 0;
      final effect =
          Effect<int, RetryFailure>.result((_) async {
            attempts++;
            return 42;
          }).retry(
            RetryPolicy.fixed(
              maxAttempts: 3,
              delay: const Duration(seconds: 1),
            ),
          );

      expect(attempts, 0);
      final exit = await Module(const <Binding>[]).runExit(effect);

      expect(expectExitSuccess(exit), 42);
      expect(attempts, 1);
    });

    test('retries a typed failure and succeeds with a manual clock', () async {
      final clock = ManualEffectClock();
      final harness = await TestRuntime.start(
        Module([.instance<EffectClock>(clock)]),
        registerCleanup: (cleanup) => addTearDown(cleanup),
      );
      var attempts = 0;
      final scheduled = harness.observer.next<RetryEvent>(
        where: (event) => event.decision == RetryDecision.retryScheduled,
      );
      final effect =
          Effect<int, RetryFailure>.result((use) async {
            attempts++;
            if (attempts == 1) use.fail(const RetryFailure(1));
            return 42;
          }).retry(
            RetryPolicy.fixed(
              maxAttempts: 2,
              delay: const Duration(seconds: 5),
            ),
          );

      final execution = harness.execute(effect, label: 'manual-retry');
      final event = await scheduled;
      await _waitForPendingSleeps(clock, 1);

      expect(event.attempt, 1);
      expect(event.previousFailure, isA<RetryFailure>());
      expect(event.plannedDelay, const Duration(seconds: 5));
      expect(event.context.executionLabel, 'manual-retry');
      expect(execution.isRunning, isTrue);

      await clock.advance(const Duration(seconds: 5));

      expect(expectExitSuccess(await execution.exit), 42);
      expect(attempts, 2);
      await _waitForPhysicalCompletion(execution);
    });

    test('exhausts maxAttempts including the initial attempt', () async {
      var attempts = 0;
      final effect = Effect<int, RetryFailure>.result((use) async {
        attempts++;
        use.fail(RetryFailure(attempts));
      }).retry(RetryPolicy.fixed(maxAttempts: 3, delay: Duration.zero));

      final exit = await Module(const <Binding>[]).runExit(effect);

      expect(expectExitFailure(exit).code, 3);
      expect(attempts, 3);
    });

    test('none and maxAttempts one do not retry', () async {
      var noneAttempts = 0;
      var singleAttempts = 0;
      final none = Effect<int, RetryFailure>.result((use) async {
        noneAttempts++;
        use.fail(const RetryFailure(1));
      }).retry(RetryPolicy.none());
      final single = Effect<int, RetryFailure>.result((use) async {
        singleAttempts++;
        use.fail(const RetryFailure(2));
      }).retry(RetryPolicy.fixed(maxAttempts: 1, delay: Duration.zero));
      final module = Module(const <Binding>[]);

      expect(expectExitFailure(await module.runExit(none)).code, 1);
      expect(expectExitFailure(await module.runExit(single)).code, 2);
      expect(noneAttempts, 1);
      expect(singleAttempts, 1);
    });

    test('whileError stops without changing the typed error', () async {
      var attempts = 0;
      final effect =
          Effect<int, RetryFailure>.result((use) async {
            attempts++;
            use.fail(const RetryFailure(400));
          }).retry(
            RetryPolicy.fixed(maxAttempts: 5, delay: Duration.zero),
            whileError: (error) => error.code >= 500,
          );

      final exit = await Module(const <Binding>[]).runExit(effect);

      expect(expectExitFailure(exit).code, 400);
      expect(attempts, 1);
    });

    test('defects are never retried', () async {
      var attempts = 0;
      final effect = Effect<int, RetryFailure>.sync(() {
        attempts++;
        throw StateError('attempt defect');
      }).retry(RetryPolicy.fixed(maxAttempts: 5, delay: Duration.zero));

      final exit = await Module(const <Binding>[]).runExit(effect);
      final defect = expectExitDefect(exit).defect;

      expect(defect, isA<StateError>());
      expect((defect as StateError).message, 'attempt defect');
      expect(attempts, 1);
    });

    test('attempt resources close before the next attempt starts', () async {
      final events = TestEventRecorder<String>();
      var attempts = 0;
      final effect = Effect<int, RetryFailure>.result((use) async {
        attempts++;
        final attempt = attempts;
        final resource = await use.acquire(
          Effect<RetryResource, RetryFailure>.sync(() {
            events.record('acquire:$attempt');
            return RetryResource(attempt);
          }),
          release: (resource, _) {
            events.record('release:${resource.attempt}');
          },
        );
        events.record('use:${resource.attempt}');
        if (attempt == 1) use.fail(const RetryFailure(1));
        return 42;
      }).retry(RetryPolicy.fixed(maxAttempts: 2, delay: Duration.zero));

      final exit = await Module(const <Binding>[]).runExit(effect);

      expect(expectExitSuccess(exit), 42);
      events.expectEvents(const <String>[
        'acquire:1',
        'use:1',
        'release:1',
        'acquire:2',
        'use:2',
        'release:2',
      ]);
    });

    test(
      'cleanup failure preserves a typed failure and prevents another attempt',
      () async {
        final diagnostics = <CleanupFailureDiagnostic>[];
        final observer = RecordingRuntimeObserver();
        var attempts = 0;
        final runtime = await Module(const <Binding>[]).start(
          observers: <RuntimeObserver>[observer],
          cleanupFailureObserver: diagnostics.add,
        );
        addTearDown(runtime.close);
        final effect = Effect<int, RetryFailure>.result((use) async {
          attempts++;
          await use.acquire(
            Effect<RetryResource, RetryFailure>.succeed(
              RetryResource(attempts),
            ),
            release: (_, _) => throw StateError('attempt cleanup failed'),
          );
          use.fail(const RetryFailure(503));
        }).retry(RetryPolicy.fixed(maxAttempts: 3, delay: Duration.zero));

        final exit = await runtime.runExit(effect, executionLabel: 'cleanup');

        expect(expectExitFailure(exit).code, 503);
        expect(attempts, 1);
        expect(diagnostics, hasLength(1));
        expect(diagnostics.single.executionLabel, 'cleanup');
        expect(
          observer.eventsOf<RetryEvent>().last.decision,
          RetryDecision.cleanupFailed,
        );
      },
    );

    test('cleanup failure after success becomes a defect', () async {
      final effect = Effect<int, RetryFailure>.result((use) async {
        await use.acquire(
          Effect<RetryResource, RetryFailure>.succeed(const RetryResource(1)),
          release: (_, _) => throw StateError('success cleanup failed'),
        );
        return 42;
      }).retry(RetryPolicy.none());

      final exit = await Module(const <Binding>[]).runExit(effect);

      expect(expectExitDefect(exit).defect, isA<ScopeReleaseException>());
    });

    test('interruption during an active attempt stops retrying', () async {
      final harness = await TestRuntime.start(
        Module(const <Binding>[]),
        registerCleanup: (cleanup) => addTearDown(cleanup),
      );
      final started = TestSignal();
      var attempts = 0;
      final effect = Effect<int, RetryFailure>.result((use) async {
        attempts++;
        started.signal();
        await use.cancellation.whenCancelled;
        use.cancellation.throwIfCancelled();
        return 1;
      }).retry(RetryPolicy.fixed(maxAttempts: 3, delay: Duration.zero));

      final execution = harness.execute(effect, label: 'active-attempt');
      await started.wait;
      expect(execution.interrupt(reason: 'test-owner'), isTrue);
      expect(await execution.exit, isExitInterrupted<int, RetryFailure>());
      await _waitForPhysicalCompletion(execution);

      expect(attempts, 1);
      expect(
        harness.observer.eventsOf<RetryEvent>().last.decision,
        RetryDecision.interrupted,
      );
    });

    test('interruption during delay prevents the next attempt', () async {
      final clock = ManualEffectClock();
      final harness = await TestRuntime.start(
        Module([.instance<EffectClock>(clock)]),
        registerCleanup: (cleanup) => addTearDown(cleanup),
      );
      var attempts = 0;
      final scheduled = harness.observer.next<RetryEvent>(
        where: (event) => event.decision == RetryDecision.retryScheduled,
      );
      final effect =
          Effect<int, RetryFailure>.result((use) async {
            attempts++;
            use.fail(const RetryFailure(1));
          }).retry(
            RetryPolicy.fixed(
              maxAttempts: 3,
              delay: const Duration(minutes: 1),
            ),
          );

      final execution = harness.execute(effect, label: 'retry-delay');
      await scheduled;
      await _waitForPendingSleeps(clock, 1);
      expect(execution.interrupt(reason: 'test-owner'), isTrue);
      expect(await execution.exit, isExitInterrupted<int, RetryFailure>());
      await _waitForPhysicalCompletion(execution);

      expect(attempts, 1);
      expect(clock.pendingSleepCount, 0);
      expect(
        harness.observer.eventsOf<RetryEvent>().last.decision,
        RetryDecision.interrupted,
      );
    });

    test(
      'a positive delay requires an explicitly installed EffectClock',
      () async {
        final effect = Effect<int, RetryFailure>.fail(const RetryFailure(1))
            .retry(
              RetryPolicy.fixed(
                maxAttempts: 2,
                delay: const Duration(milliseconds: 1),
              ),
            );

        final exit = await Module(const <Binding>[]).runExit(effect);

        expect(expectExitDefect(exit).defect, isNotNull);
      },
    );

    test(
      'full jitter uses EffectRandom and the planned delay is observable',
      () async {
        final clock = ManualEffectClock();
        final random = _SequenceRandom(const <double>[0.5]);
        final harness = await TestRuntime.start(
          Module([
            .instance<EffectClock>(clock),
            .instance<EffectRandom>(random),
          ]),
          registerCleanup: (cleanup) => addTearDown(cleanup),
        );
        var attempts = 0;
        final scheduled = harness.observer.next<RetryEvent>(
          where: (event) => event.decision == RetryDecision.retryScheduled,
        );
        final effect =
            Effect<int, RetryFailure>.result((use) async {
              attempts++;
              if (attempts == 1) use.fail(const RetryFailure(1));
              return 42;
            }).retry(
              RetryPolicy.fixed(
                maxAttempts: 2,
                delay: const Duration(seconds: 10),
                jitter: true,
              ),
            );

        final execution = harness.execute(effect);
        final event = await scheduled;
        await _waitForPendingSleeps(clock, 1);

        expect(event.plannedDelay, const Duration(seconds: 5));
        expect(random.calls, 1);
        await clock.advance(const Duration(seconds: 5));
        expect(expectExitSuccess(await execution.exit), 42);
      },
    );

    test(
      'jitter requires EffectRandom only when randomness is requested',
      () async {
        final clock = ManualEffectClock();
        final effect = Effect<int, RetryFailure>.fail(const RetryFailure(1))
            .retry(
              RetryPolicy.fixed(
                maxAttempts: 2,
                delay: const Duration(seconds: 1),
                jitter: true,
              ),
            );

        final exit = await Module([
          .instance<EffectClock>(clock),
        ]).runExit(effect);

        expect(expectExitDefect(exit).defect, isNotNull);
      },
    );

    test(
      'custom policies participate without changing the Effect type',
      () async {
        var attempts = 0;
        final effect = Effect<int, RetryFailure>.result((use) async {
          attempts++;
          if (attempts == 1) use.fail(const RetryFailure(1));
          return 42;
        }).retry(const _TwoAttemptPolicy());

        final exit = await Module(const <Binding>[]).runExit(effect);

        expect(expectExitSuccess(exit), 42);
        expect(attempts, 2);
      },
    );

    test('a custom negative delay remains a defect', () async {
      final effect = Effect<int, RetryFailure>.fail(
        const RetryFailure(1),
      ).retry(const _NegativeDelayPolicy());

      final exit = await Module(const <Binding>[]).runExit(effect);

      expect(expectExitDefect(exit).defect, isA<ArgumentError>());
    });

    test(
      'RetryEvent exposes attempt decisions and execution identity',
      () async {
        final observer = RecordingRuntimeObserver();
        final runtime = await Module(
          const <Binding>[],
        ).start(observers: <RuntimeObserver>[observer]);
        addTearDown(runtime.close);
        var attempts = 0;
        final effect = Effect<int, RetryFailure>.result((use) async {
          attempts++;
          if (attempts == 1) use.fail(const RetryFailure(1));
          return 42;
        }).retry(RetryPolicy.fixed(maxAttempts: 2, delay: Duration.zero));

        final exit = await runtime.runExit(
          effect,
          executionLabel: 'observable',
        );
        final events = observer.eventsOf<RetryEvent>().toList();

        expect(expectExitSuccess(exit), 42);
        expect(events.map((event) => event.attempt), <int>[1, 2]);
        expect(events.map((event) => event.decision), <RetryDecision>[
          RetryDecision.retryScheduled,
          RetryDecision.succeeded,
        ]);
        expect(
          events.every(
            (event) =>
                event.context.executionId > 0 &&
                event.context.executionLabel == 'observable',
          ),
          isTrue,
        );
      },
    );
  });

  group('RetryPolicy', () {
    RetryContext<RetryFailure> context(int attempt, {double random = 0.5}) {
      return RetryContext<RetryFailure>(
        attempt: attempt,
        error: RetryFailure(attempt),
        nextRandom: () => random,
      );
    }

    test('fixed, linear, and exponential delays are deterministic', () {
      final RetryPolicy<RetryFailure> fixed = RetryPolicy.fixed(
        maxAttempts: 4,
        delay: const Duration(milliseconds: 100),
      );
      final RetryPolicy<RetryFailure> linear = RetryPolicy.linear(
        maxAttempts: 4,
        initialDelay: const Duration(milliseconds: 100),
        increment: const Duration(milliseconds: 50),
      );
      final RetryPolicy<RetryFailure> exponential = RetryPolicy.exponential(
        maxAttempts: 4,
        initialDelay: const Duration(milliseconds: 100),
      );

      expect(fixed.nextDelay(context(1)), const Duration(milliseconds: 100));
      expect(fixed.nextDelay(context(3)), const Duration(milliseconds: 100));
      expect(fixed.nextDelay(context(4)), isNull);

      expect(linear.nextDelay(context(1)), const Duration(milliseconds: 100));
      expect(linear.nextDelay(context(2)), const Duration(milliseconds: 150));
      expect(linear.nextDelay(context(3)), const Duration(milliseconds: 200));

      expect(
        exponential.nextDelay(context(1)),
        const Duration(milliseconds: 100),
      );
      expect(
        exponential.nextDelay(context(2)),
        const Duration(milliseconds: 200),
      );
      expect(
        exponential.nextDelay(context(3)),
        const Duration(milliseconds: 400),
      );
    });

    test('maxDelay caps linear and exponential policies before jitter', () {
      final RetryPolicy<RetryFailure> linear = RetryPolicy.linear(
        maxAttempts: 10,
        initialDelay: const Duration(seconds: 2),
        increment: const Duration(seconds: 3),
        maxDelay: const Duration(seconds: 5),
      );
      final RetryPolicy<RetryFailure> exponential = RetryPolicy.exponential(
        maxAttempts: 10,
        initialDelay: const Duration(seconds: 2),
        maxDelay: const Duration(seconds: 5),
      );

      expect(linear.nextDelay(context(4)), const Duration(seconds: 5));
      expect(exponential.nextDelay(context(4)), const Duration(seconds: 5));
    });

    test('seeded randomness reproduces full-jitter decisions', () {
      final firstRandom = SeededEffectRandom(42);
      final secondRandom = SeededEffectRandom(42);
      final RetryPolicy<RetryFailure> policy = RetryPolicy.exponential(
        maxAttempts: 3,
        initialDelay: const Duration(seconds: 10),
        jitter: true,
      );

      final first = policy.nextDelay(
        RetryContext<RetryFailure>(
          attempt: 1,
          error: const RetryFailure(1),
          nextRandom: firstRandom.nextDouble,
        ),
      );
      final second = policy.nextDelay(
        RetryContext<RetryFailure>(
          attempt: 1,
          error: const RetryFailure(1),
          nextRandom: secondRandom.nextDouble,
        ),
      );

      expect(first, second);
      expect(first, isNot(const Duration(seconds: 10)));
    });

    test('invalid policy configuration is rejected immediately', () {
      expect(
        () => RetryPolicy<RetryFailure>.fixed(
          maxAttempts: 0,
          delay: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => RetryPolicy<RetryFailure>.fixed(
          maxAttempts: 2,
          delay: const Duration(microseconds: -1),
        ),
        throwsArgumentError,
      );
      expect(
        () => RetryPolicy<RetryFailure>.linear(
          maxAttempts: 2,
          initialDelay: Duration.zero,
          increment: const Duration(microseconds: -1),
        ),
        throwsArgumentError,
      );
      expect(
        () => RetryPolicy<RetryFailure>.exponential(
          maxAttempts: 2,
          initialDelay: Duration.zero,
          factor: 0,
        ),
        throwsArgumentError,
      );
    });

    test('overflow is rejected without maxDelay and capped with it', () {
      final RetryPolicy<RetryFailure> uncapped = RetryPolicy.exponential(
        maxAttempts: 20,
        initialDelay: const Duration(days: 1),
        factor: 1000000000,
      );
      final RetryPolicy<RetryFailure> capped = RetryPolicy.exponential(
        maxAttempts: 20,
        initialDelay: const Duration(days: 1),
        factor: 1000000000,
        maxDelay: const Duration(days: 30),
      );

      expect(() => uncapped.nextDelay(context(4)), throwsRangeError);
      expect(capped.nextDelay(context(4)), const Duration(days: 30));
    });

    test('RetryContext validates random implementations', () {
      final RetryPolicy<RetryFailure> policy = RetryPolicy.fixed(
        maxAttempts: 2,
        delay: const Duration(seconds: 1),
        jitter: true,
      );

      expect(
        () => policy.nextDelay(context(1, random: double.nan)),
        throwsStateError,
      );
      expect(() => policy.nextDelay(context(1, random: 1)), throwsStateError);
    });
  });
}

Future<void> _waitForPendingSleeps(
  ManualEffectClock clock,
  int expected,
) async {
  for (
    var attempt = 0;
    attempt < 100 && clock.pendingSleepCount != expected;
    attempt++
  ) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(clock.pendingSleepCount, expected);
}

Future<void> _waitForPhysicalCompletion<A extends Object, E extends Object>(
  EffectExecution<A, E> execution,
) async {
  while (execution.isRunning) {
    await Future<void>.delayed(Duration.zero);
  }
}
