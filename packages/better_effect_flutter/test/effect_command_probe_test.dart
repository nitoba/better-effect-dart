import 'dart:async';

import 'package:better_effect_flutter/testing.dart';
import 'package:flutter_test/flutter_test.dart';

final class ProbeFailure implements Exception {
  const ProbeFailure();
}

void main() {
  test('records Command revisions and waits for typed states', () async {
    final runtime = await Module(const <Binding>[]).start();
    final gate = Completer<int>();
    final command = EffectCommands(runtime)<int, ProbeFailure>(
      () => Effect<int, ProbeFailure>.result((_) => gate.future),
      debugLabel: 'probe.command',
    );
    final probe = EffectCommandProbe<int, ProbeFailure>(command);

    try {
      final running = probe.waitFor<EffectCommandRunning<int, ProbeFailure>>();
      final success = probe.waitFor<EffectCommandSuccess<int, ProbeFailure>>();
      final execution = command.execute();

      expect((await running).isRunning, isTrue);
      gate.complete(42);
      expect(expectExitSuccess(await execution), 42);
      expect((await success).value, 42);
      expect(probe.states, hasLength(3));
      probe.expectStateTypes(<Type>[
        EffectCommandIdle<int, ProbeFailure>,
        EffectCommandRunning<int, ProbeFailure>,
        EffectCommandSuccess<int, ProbeFailure>,
      ]);
      expect(
        probe.states.map((state) => state.revision),
        orderedEquals(<int>[0, 1, 2]),
      );
    } finally {
      probe.dispose();
      command.dispose();
      await runtime.close();
    }
  });

  test(
    'nextWhere ignores previous history and clear resets snapshots',
    () async {
      final runtime = await Module(const <Binding>[]).start();
      final command = EffectCommands(runtime)<int, ProbeFailure>(
        () => Effect<int, ProbeFailure>.succeed(1),
      );
      final probe = EffectCommandProbe<int, ProbeFailure>(command);

      try {
        await command.execute();
        expect(probe.states, hasLength(3));

        final nextRunning = probe.nextWhere((state) => state.isRunning);
        probe.clear();
        final execution = command.execute();

        expect(
          await nextRunning,
          isA<EffectCommandRunning<int, ProbeFailure>>(),
        );
        await execution;
        expect(probe.states, hasLength(2));
        expect(probe.lastState, isA<EffectCommandSuccess<int, ProbeFailure>>());
      } finally {
        probe.dispose();
        command.dispose();
        await runtime.close();
      }
    },
  );

  test(
    'disposing a probe fails pending waiters without disposing the Command',
    () async {
      final runtime = await Module(const <Binding>[]).start();
      final command = EffectCommands(runtime)<int, ProbeFailure>(
        () => Effect<int, ProbeFailure>.succeed(1),
      );
      final probe = EffectCommandProbe<int, ProbeFailure>(command);
      final pending = probe.nextWhere(
        (state) => state is EffectCommandFailure<int, ProbeFailure>,
      );

      probe.dispose();

      await expectLater(
        pending,
        throwsA(isA<EffectCommandProbeDisposedException>()),
      );
      expect(command.isDisposed, isFalse);

      command.dispose();
      await runtime.close();
    },
  );
}
