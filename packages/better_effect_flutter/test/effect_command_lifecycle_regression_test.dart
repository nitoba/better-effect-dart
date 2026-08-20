import 'dart:async';

import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

final class CommandRegressionFailure implements Exception {
  const CommandRegressionFailure();
}

final class CommandRegressionResource {
  const CommandRegressionResource(this.id);

  final int id;
}

void main() {
  group('v0.2 execution safety — Command queue cancellation', () {
    test(
      'clearQueued interrupts active and queued callers without starting them',
      () async {
        final runtime = await Module(const <Binding>[]).start();
        final commands = EffectCommands(runtime);
        final firstStarted = Completer<void>();
        final continueFirstPhysicalWork = Completer<void>();
        final startedInputs = <int>[];
        final command = commands.withInput<int, int, CommandRegressionFailure>(
          (input) => Effect<int, CommandRegressionFailure>.result((use) async {
            startedInputs.add(input);
            if (input == 1) {
              firstStarted.complete();
              await use.cancellation.whenCancelled;
              await continueFirstPhysicalWork.future;
            }
            return input;
          }),
          concurrency: EffectCommandConcurrency.queue,
        );
        addTearDown(command.dispose);

        final first = command.execute(1);
        await firstStarted.future;
        final second = command.execute(2);
        final third = command.execute(3);

        expect(command.queuedCount, 2);
        expect(command.cancel(clearQueued: true), isTrue);
        expect(
          await first,
          isA<ExitInterrupted<int, CommandRegressionFailure>>(),
        );
        expect(
          await second,
          isA<ExitInterrupted<int, CommandRegressionFailure>>(),
        );
        expect(
          await third,
          isA<ExitInterrupted<int, CommandRegressionFailure>>(),
        );
        expect(command.pendingCount, 0);
        expect(command.queuedCount, 0);
        expect(startedInputs, <int>[1]);

        continueFirstPhysicalWork.complete();
        await runtime.close();

        expect(startedInputs, <int>[1]);
        expect(
          command.value,
          isA<EffectCommandInterrupted<int, CommandRegressionFailure>>(),
        );
      },
    );

    test(
      'preserving the queue starts the next caller and keeps request order',
      () async {
        final runtime = await Module(const <Binding>[]).start();
        final commands = EffectCommands(runtime);
        final firstStarted = Completer<void>();
        final secondStarted = Completer<void>();
        final thirdStarted = Completer<void>();
        final continueFirstPhysicalWork = Completer<void>();
        final continueSecond = Completer<void>();
        final startedInputs = <int>[];
        final command = commands.withInput<int, int, CommandRegressionFailure>(
          (input) => Effect<int, CommandRegressionFailure>.result((use) async {
            startedInputs.add(input);
            if (input == 1) {
              firstStarted.complete();
              await use.cancellation.whenCancelled;
              await continueFirstPhysicalWork.future;
            } else if (input == 2) {
              secondStarted.complete();
              await continueSecond.future;
            } else {
              thirdStarted.complete();
            }
            return input;
          }),
          concurrency: EffectCommandConcurrency.queue,
        );
        addTearDown(command.dispose);

        final first = command.execute(1);
        await firstStarted.future;
        final second = command.execute(2);
        final third = command.execute(3);

        expect(command.cancel(clearQueued: false), isTrue);
        expect(
          await first,
          isA<ExitInterrupted<int, CommandRegressionFailure>>(),
        );
        await secondStarted.future;

        expect(startedInputs, <int>[1, 2]);
        expect(command.queuedCount, 1);

        continueFirstPhysicalWork.complete();
        continueSecond.complete();

        expect(await second, isA<ExitSuccess<int, CommandRegressionFailure>>());
        await thirdStarted.future;
        expect(await third, isA<ExitSuccess<int, CommandRegressionFailure>>());

        await runtime.close();

        expect(startedInputs, <int>[1, 2, 3]);
        expect(command.data, 3);
        expect(command.pendingCount, 0);
      },
    );
  });

  group('v0.2 execution safety — Command physical ownership', () {
    test(
      'cancel keeps an acquired resource alive until physical work finishes',
      () async {
        final runtime = await Module(const <Binding>[]).start();
        final commands = EffectCommands(runtime);
        final executionStarted = Completer<void>();
        final cancellationObserved = Completer<Object?>();
        final continuePhysicalWork = Completer<void>();
        var releases = 0;
        final command = commands<int, CommandRegressionFailure>(
          () => Effect<int, CommandRegressionFailure>.result((use) async {
            await use.acquire(
              Effect<
                CommandRegressionResource,
                CommandRegressionFailure
              >.succeed(const CommandRegressionResource(1)),
              release: (_, _) {
                releases++;
              },
            );
            executionStarted.complete();
            await use.cancellation.whenCancelled;
            cancellationObserved.complete(use.cancellation.reason);
            await continuePhysicalWork.future;
            return 42;
          }),
        );
        addTearDown(command.dispose);

        final running = command.execute();
        await executionStarted.future;

        expect(command.cancel(), isTrue);
        expect(
          await running,
          isA<ExitInterrupted<int, CommandRegressionFailure>>(),
        );
        expect(await cancellationObserved.future, 'command-cancelled');
        expect(releases, 0);

        final closing = runtime.close();
        expect(runtime.state, RuntimeState.closing);
        expect(releases, 0);

        continuePhysicalWork.complete();
        await closing;

        expect(releases, 1);
        expect(runtime.state, RuntimeState.closed);
        expect(
          command.value,
          isA<EffectCommandInterrupted<int, CommandRegressionFailure>>(),
        );
      },
    );

    test(
      'dispose and Runtime shutdown preserve the first cancellation reason',
      () async {
        final runtime = await Module(const <Binding>[]).start();
        final commands = EffectCommands(runtime);
        final executionStarted = Completer<void>();
        final cancellationObserved = Completer<Object?>();
        final continuePhysicalWork = Completer<void>();
        var releases = 0;
        final command = commands<int, CommandRegressionFailure>(
          () => Effect<int, CommandRegressionFailure>.result((use) async {
            await use.acquire(
              Effect<
                CommandRegressionResource,
                CommandRegressionFailure
              >.succeed(const CommandRegressionResource(1)),
              release: (_, _) {
                releases++;
              },
            );
            executionStarted.complete();
            await use.cancellation.whenCancelled;
            cancellationObserved.complete(use.cancellation.reason);
            await continuePhysicalWork.future;
            return 42;
          }),
        );

        final running = command.execute();
        await executionStarted.future;

        command.dispose();
        final closing = runtime.close(
          gracePeriod: Duration.zero,
          interruptAfterGracePeriod: true,
        );

        expect(
          await running,
          isA<ExitInterrupted<int, CommandRegressionFailure>>(),
        );
        expect(await cancellationObserved.future, 'command-disposed');
        expect(command.pendingCount, 0);
        expect(releases, 0);

        continuePhysicalWork.complete();
        await closing;

        expect(releases, 1);
        expect(runtime.state, RuntimeState.closed);
      },
    );

    test(
      'cancel-first and completion-first outcomes stay stable when repeated',
      () async {
        final runtime = await Module(const <Binding>[]).start();
        final commands = EffectCommands(runtime);
        var physicalCompletions = 0;

        for (var iteration = 0; iteration < 16; iteration++) {
          final executionStarted = Completer<void>();
          final continueExecution = Completer<void>();
          final command = commands<int, CommandRegressionFailure>(
            () => Effect<int, CommandRegressionFailure>.result((_) async {
              executionStarted.complete();
              await continueExecution.future;
              physicalCompletions++;
              return iteration;
            }),
            debugLabel: 'command-race:$iteration',
          );

          final running = command.execute();
          await executionStarted.future;

          if (iteration.isEven) {
            expect(command.cancel(), isTrue);
            expect(
              await running,
              isA<ExitInterrupted<int, CommandRegressionFailure>>(),
            );
            expect(
              command.value,
              isA<EffectCommandInterrupted<int, CommandRegressionFailure>>(),
            );
            continueExecution.complete();
          } else {
            continueExecution.complete();
            final exit = await running;
            expect(exit, isA<ExitSuccess<int, CommandRegressionFailure>>());
            expect(
              (exit as ExitSuccess<int, CommandRegressionFailure>).value,
              iteration,
            );
            expect(command.cancel(), isFalse);
            expect(
              command.value,
              isA<EffectCommandSuccess<int, CommandRegressionFailure>>(),
            );
          }

          command.dispose();
        }

        await runtime.close();
        expect(physicalCompletions, 16);
      },
    );
  });

  group('v0.2 execution safety — latest authority', () {
    test(
      'stale completions never replace the latest value in bounded repetitions',
      () async {
        final runtime = await Module(const <Binding>[]).start();
        final commands = EffectCommands(runtime);

        for (var iteration = 0; iteration < 8; iteration++) {
          final firstGate = Completer<int>();
          final secondGate = Completer<int>();
          final command = commands
              .withInput<int, int, CommandRegressionFailure>(
                (input) => Effect<int, CommandRegressionFailure>.result(
                  (_) => input == 1 ? firstGate.future : secondGate.future,
                ),
                concurrency: EffectCommandConcurrency.latest,
              );

          final first = command.execute(1);
          final second = command.execute(2);

          secondGate.complete(iteration * 10 + 2);
          final secondExit = await second;
          expect(secondExit, isA<ExitSuccess<int, CommandRegressionFailure>>());

          firstGate.complete(iteration * 10 + 1);
          final firstExit = await first;
          expect(firstExit, isA<ExitSuccess<int, CommandRegressionFailure>>());
          expect(command.data, iteration * 10 + 2);

          command.dispose();
        }

        await runtime.close();
      },
    );
  });
}
