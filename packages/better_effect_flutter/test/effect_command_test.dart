import 'dart:async';

import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class TestFailure implements Exception {
  const TestFailure();
}

final class ExpectedFailure extends TestFailure {
  const ExpectedFailure(this.message);

  final String message;
}

void main() {
  late Runtime runtime;
  late EffectCommands commands;

  setUp(() async {
    runtime = await Module(const <Binding>[]).start();
    commands = EffectCommands(runtime);
  });

  tearDown(() async {
    await runtime.close();
  });

  test('starts idle and publishes typed success', () async {
    final command = commands<int, TestFailure>(
      () => Effect<int, TestFailure>.succeed(42),
    );
    addTearDown(command.dispose);

    expect(command.value, isA<EffectCommandIdle<int, TestFailure>>());

    final exit = await command.execute();

    expect(exit, isA<ExitSuccess<int, TestFailure>>());
    expect(command.value, isA<EffectCommandSuccess<int, TestFailure>>());
    expect(command.data, 42);
    expect(command.resultOrNull?.getOrNull(), 42);
  });

  test('preserves a typed failure separately from defects', () async {
    const failure = ExpectedFailure('expected');
    final command = commands<int, TestFailure>(
      () => Effect<int, TestFailure>.fail(failure),
    );
    addTearDown(command.dispose);

    final exit = await command.execute();

    expect(exit, isA<ExitFailure<int, TestFailure>>());
    expect(command.value, isA<EffectCommandFailure<int, TestFailure>>());
    expect(command.error, same(failure));
    expect(command.lastDefect, isNull);
  });

  test('preserves unexpected defects', () async {
    final command = commands<int, TestFailure>(
      () => Effect<int, TestFailure>.sync(
        () => throw StateError('boom'),
      ),
    );
    addTearDown(command.dispose);

    final exit = await command.execute();

    expect(exit, isA<ExitDefect<int, TestFailure>>());
    expect(command.value, isA<EffectCommandDefect<int, TestFailure>>());
    expect(command.lastDefect, isA<StateError>());
    expect(command.resultOrNull, isNull);
  });

  test('drop returns the active execution instead of duplicating work', () async {
    final gate = Completer<int>();
    var starts = 0;

    final command = commands<int, TestFailure>(
      () => Effect<int, TestFailure>.result((_) async {
        starts++;
        return gate.future;
      }),
    );
    addTearDown(command.dispose);

    final first = command.execute();
    final second = command.execute();

    expect(identical(first, second), isTrue);
    gate.complete(1);

    await first;
    expect(starts, 1);
  });

  test('latest ignores stale completions in visible state', () async {
    final firstGate = Completer<int>();
    final secondGate = Completer<int>();

    final command = commands.withInput<int, int, TestFailure>(
      (input) => Effect<int, TestFailure>.result(
        (_) => input == 1 ? firstGate.future : secondGate.future,
      ),
      concurrency: EffectCommandConcurrency.latest,
    );
    addTearDown(command.dispose);

    final first = command.execute(1);
    final second = command.execute(2);

    secondGate.complete(2);
    await second;
    expect(command.data, 2);

    firstGate.complete(1);
    await first;
    expect(command.data, 2);
  });

  test('queue serializes executions in request order', () async {
    final firstGate = Completer<void>();
    final secondGate = Completer<void>();
    final started = <int>[];
    final completed = <int>[];

    final command = commands.withInput<int, int, TestFailure>(
      (input) => Effect<int, TestFailure>.result((_) async {
        started.add(input);
        await (input == 1 ? firstGate.future : secondGate.future);
        completed.add(input);
        return input;
      }),
      concurrency: EffectCommandConcurrency.queue,
    );
    addTearDown(command.dispose);

    final first = command.execute(1);
    final second = command.execute(2);
    await Future<void>.delayed(Duration.zero);

    expect(started, <int>[1]);
    expect(command.queuedCount, 1);

    firstGate.complete();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(started, <int>[1, 2]);

    secondGate.complete();
    await second;
    expect(completed, <int>[1, 2]);
    expect(command.data, 2);
  });

  test('cancel interrupts ownership and ignores a late completion', () async {
    final gate = Completer<int>();
    var cancelled = false;

    final command = commands<int, TestFailure>(
      () => Effect<int, TestFailure>.result((_) => gate.future),
      onCancel: () => cancelled = true,
    );
    addTearDown(command.dispose);

    final running = command.execute();
    expect(command.cancel(), isTrue);
    expect(cancelled, isTrue);
    expect(command.value, isA<EffectCommandInterrupted<int, TestFailure>>());

    final interrupted = await running;
    expect(interrupted, isA<ExitInterrupted<int, TestFailure>>());

    gate.complete(99);
    await Future<void>.delayed(Duration.zero);

    expect(command.value, isA<EffectCommandInterrupted<int, TestFailure>>());
    expect(command.data, isNull);
  });

  test('dispose interrupts every pending latest caller', () async {
    final firstGate = Completer<int>();
    final secondGate = Completer<int>();

    final command = commands.withInput<int, int, TestFailure>(
      (input) => Effect<int, TestFailure>.result(
        (_) => input == 1 ? firstGate.future : secondGate.future,
      ),
      concurrency: EffectCommandConcurrency.latest,
    );

    final first = command.execute(1);
    final second = command.execute(2);

    expect(command.pendingCount, 2);
    command.dispose();

    expect(await first, isA<ExitInterrupted<int, TestFailure>>());
    expect(await second, isA<ExitInterrupted<int, TestFailure>>());
    expect(command.pendingCount, 0);

    firstGate.complete(1);
    secondGate.complete(2);
    await Future<void>.delayed(Duration.zero);
  });

  test('drop remembers the input that actually started', () async {
    final gate = Completer<int>();
    final started = <int>[];

    final command = commands.withInput<int, int, TestFailure>(
      (input) {
        started.add(input);
        return Effect<int, TestFailure>.result((_) => gate.future);
      },
    );
    addTearDown(command.dispose);

    final first = command.execute(1);
    final dropped = command.execute(2);

    expect(identical(first, dropped), isTrue);
    expect(command.lastInputOrNull, 1);
    expect(started, <int>[1]);

    gate.complete(1);
    await first;
  });

  test('input command can retry its latest input', () async {
    var calls = 0;
    final command = commands.withInput<String, int, TestFailure>(
      (input) => Effect<int, TestFailure>.sync(() {
        calls++;
        return input.length;
      }),
    );
    addTearDown(command.dispose);

    await command.execute('dart');
    await command.retry();

    expect(calls, 2);
    expect(command.data, 4);
    expect(command.lastInputOrNull, 'dart');
  });

  test('global observer receives labeled state transitions', () async {
    final transitions = <EffectCommandTransition>[];
    final observedCommands = EffectCommands(
      runtime,
      observer: transitions.add,
    );
    final command = observedCommands<int, TestFailure>(
      () => Effect<int, TestFailure>.succeed(5),
      debugLabel: 'observed-command',
    );
    addTearDown(command.dispose);

    await command.execute();

    expect(transitions, hasLength(2));
    expect(
      transitions.first.current,
      isA<EffectCommandRunning<int, TestFailure>>(),
    );
    expect(
      transitions.last.current,
      isA<EffectCommandSuccess<int, TestFailure>>(),
    );
    expect(
      transitions.every(
        (transition) => transition.debugLabel == 'observed-command',
      ),
      isTrue,
    );
  });

  test('reset can retain or clear the latest successful data', () async {
    final command = commands<int, TestFailure>(
      () => Effect<int, TestFailure>.succeed(7),
    );
    addTearDown(command.dispose);

    await command.execute();
    expect(command.reset(), isTrue);
    expect(command.value.dataOrNull, 7);

    expect(command.clear(), isTrue);
    expect(command.value.dataOrNull, isNull);
  });
}
