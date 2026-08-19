import 'dart:async';

import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

final class CommandFailure implements Exception {
  const CommandFailure();
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

  test('Command.cancel reaches the core cancellation signal', () async {
    final started = Completer<void>();
    final cancellationObserved = Completer<Object?>();
    final command = commands<int, CommandFailure>(
      () => Effect<int, CommandFailure>.result((use) async {
        started.complete();
        await use.cancellation.whenCancelled;
        cancellationObserved.complete(use.cancellation.reason);
        return 42;
      }),
      debugLabel: 'managed-command',
    );
    addTearDown(command.dispose);

    final running = command.execute();
    await started.future;

    expect(command.cancel(), isTrue);
    expect(await running, isA<ExitInterrupted<int, CommandFailure>>());
    expect(await cancellationObserved.future, 'command-cancelled');
    expect(command.value, isA<EffectCommandInterrupted<int, CommandFailure>>());
  });

  test('disposing a Command interrupts its authoritative execution', () async {
    final started = Completer<void>();
    final cancellationObserved = Completer<Object?>();
    final command = commands<int, CommandFailure>(
      () => Effect<int, CommandFailure>.result((use) async {
        started.complete();
        await use.cancellation.whenCancelled;
        cancellationObserved.complete(use.cancellation.reason);
        return 42;
      }),
    );

    final running = command.execute();
    await started.future;
    command.dispose();

    expect(await running, isA<ExitInterrupted<int, CommandFailure>>());
    expect(await cancellationObserved.future, 'command-disposed');
  });

  test('Runtime shutdown interrupts the visible Command state', () async {
    final started = Completer<void>();
    final command = commands<int, CommandFailure>(
      () => Effect<int, CommandFailure>.result((use) async {
        started.complete();
        await use.cancellation.whenCancelled;
        use.cancellation.throwIfCancelled();
        return 42;
      }),
    );
    addTearDown(command.dispose);

    final running = command.execute();
    await started.future;
    final closing = runtime.close(
      gracePeriod: Duration.zero,
      interruptAfterGracePeriod: true,
    );

    expect(await running, isA<ExitInterrupted<int, CommandFailure>>());
    await closing;
    expect(command.value, isA<EffectCommandInterrupted<int, CommandFailure>>());
  });

  test('latest does not interrupt stale physical work by default', () async {
    final firstStarted = Completer<void>();
    final firstGate = Completer<void>();
    final secondGate = Completer<void>();
    var firstWasCancelled = false;

    final command = commands.withInput<int, int, CommandFailure>(
      (input) => Effect<int, CommandFailure>.result((use) async {
        if (input == 1) {
          firstStarted.complete();
          await firstGate.future;
          firstWasCancelled = use.cancellation.isCancelled;
          return 1;
        }

        await secondGate.future;
        return 2;
      }),
      concurrency: EffectCommandConcurrency.latest,
    );
    addTearDown(command.dispose);

    final first = command.execute(1);
    await firstStarted.future;
    final second = command.execute(2);

    secondGate.complete();
    await second;
    firstGate.complete();
    await first;

    expect(firstWasCancelled, isFalse);
    expect(command.data, 2);
  });

  test('onCancel remains an adapter hook and can surface a defect', () async {
    final started = Completer<void>();
    final continueExecution = Completer<void>();
    final command = commands<int, CommandFailure>(
      () => Effect<int, CommandFailure>.result((_) async {
        started.complete();
        await continueExecution.future;
        return 42;
      }),
      onCancel: () => throw StateError('adapter failed'),
    );
    addTearDown(command.dispose);

    final running = command.execute();
    await started.future;
    expect(command.cancel(), isTrue);

    expect(await running, isA<ExitDefect<int, CommandFailure>>());
    expect(command.value, isA<EffectCommandDefect<int, CommandFailure>>());

    continueExecution.complete();
  });
}
