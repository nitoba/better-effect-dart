import 'dart:async';

import 'package:better_effect/better_effect.dart';
import 'package:test/test.dart';

final class ExecutionFailure implements Exception {
  const ExecutionFailure(this.message);

  final String message;
}

final class ExecutionDefect implements Exception {
  const ExecutionDefect(this.message);

  final String message;
}

final class ExecutionResource {
  const ExecutionResource();
}

void main() {
  test('Runtime.execute exposes typed metadata and success', () async {
    final runtime = await Module(const <Binding>[]).start();

    try {
      final first = runtime.execute(
        Effect<int, Never>.succeed(42),
        label: 'answer',
      );
      final second = runtime.execute(Effect<int, Never>.succeed(7));

      expect(first.id, 1);
      expect(first.label, 'answer');
      expect(second.id, 2);
      expect(second.label, isNull);
      expect(await first.exit, isA<ExitSuccess<int, Never>>());
      expect(await second.exit, isA<ExitSuccess<int, Never>>());
    } finally {
      await runtime.close();
    }
  });

  test(
    'interrupt publishes ExitInterrupted before physical completion',
    () async {
      final started = Completer<void>();
      final continueExecution = Completer<void>();
      var released = false;
      final runtime = await Module(const <Binding>[]).start();

      final execution = runtime.execute(
        Effect<int, Never>.result((use) async {
          await use.acquire(
            Effect<ExecutionResource, Never>.succeed(const ExecutionResource()),
            release: (_, _) async {
              released = true;
            },
          );
          started.complete();
          await continueExecution.future;
          return 42;
        }),
        label: 'interruptible',
      );

      await started.future;

      expect(execution.interrupt(reason: 'user-cancelled'), isTrue);
      expect(execution.interrupt(reason: 'duplicate'), isFalse);
      expect(await execution.exit, isA<ExitInterrupted<int, Never>>());
      expect(execution.isInterrupted, isTrue);
      expect(execution.isRunning, isTrue);
      expect(released, isFalse);

      continueExecution.complete();
      await runtime.close();

      expect(execution.isRunning, isFalse);
      expect(released, isTrue);
    },
  );

  test('cooperative throwIfCancelled terminates physical work', () async {
    final started = Completer<void>();
    final runtime = await Module(const <Binding>[]).start();
    final execution = runtime.execute(
      Effect<int, Never>.result((use) async {
        started.complete();
        await use.cancellation.whenCancelled;
        use.cancellation.throwIfCancelled();
        return 42;
      }),
    );

    await started.future;
    execution.interrupt(reason: 'stop');

    expect(await execution.exit, isA<ExitInterrupted<int, Never>>());
    await runtime.close();
    expect(execution.isRunning, isFalse);
  });

  test('late typed failure cannot replace interruption', () async {
    final started = Completer<void>();
    final continueExecution = Completer<void>();
    final runtime = await Module(const <Binding>[]).start();
    final execution = runtime.execute(
      Effect<int, ExecutionFailure>.result((use) async {
        started.complete();
        await continueExecution.future;
        use.fail(const ExecutionFailure('late'));
      }),
    );

    await started.future;
    execution.interrupt();
    final exit = await execution.exit;

    continueExecution.complete();
    await runtime.close();

    expect(exit, isA<ExitInterrupted<int, ExecutionFailure>>());
  });

  test(
    'late defect remains observable without replacing interruption',
    () async {
      final started = Completer<void>();
      final continueExecution = Completer<void>();
      final runtime = await Module(const <Binding>[]).start();
      final execution = runtime.execute(
        Effect<int, Never>.result((_) async {
          started.complete();
          await continueExecution.future;
          throw const ExecutionDefect('late');
        }),
      );

      await started.future;
      execution.interrupt();
      final exit = await execution.exit;
      continueExecution.complete();

      expect(exit, isA<ExitInterrupted<int, Never>>());
      await expectLater(runtime.close(), throwsA(isA<ScopeReleaseException>()));
    },
  );

  test('Runtime shutdown interrupts managed executions after grace', () async {
    final started = Completer<void>();
    final runtime = await Module(const <Binding>[]).start();
    final execution = runtime.execute(
      Effect<int, Never>.result((use) async {
        started.complete();
        await use.cancellation.whenCancelled;
        use.cancellation.throwIfCancelled();
        return 42;
      }),
      label: 'shutdown-work',
    );

    await started.future;
    final closing = runtime.close(
      gracePeriod: Duration.zero,
      interruptAfterGracePeriod: true,
    );

    expect(await execution.exit, isA<ExitInterrupted<int, Never>>());
    await closing;

    expect(execution.isInterrupted, isTrue);
    expect(execution.isRunning, isFalse);
  });
}
