import 'package:better_effect/testing.dart';
import 'package:test/test.dart';

void main() {
  test('observer events identify child Runtime and feature label', () async {
    final recorder = RecordingRuntimeObserver();
    final root = await Module(
      const <Binding>[],
    ).start(observers: <RuntimeObserver>[recorder]);
    final child = await root.fork(Module(const <Binding>[]), label: 'checkout');

    try {
      final ended = recorder.next<ExecutionEndEvent>(
        where: (event) => event.context.executionLabel == 'checkout.load',
      );
      await child.runExit(
        Effect<int, Never>.succeed(42),
        executionLabel: 'checkout.load',
      );
      final event = await ended;

      expect(event.context.runtimeId, child.runtimeId);
      expect(event.context.parentRuntimeId, root.runtimeId);
      expect(event.context.runtimeLabel, 'checkout');
      expect(event.context.executionLabel, 'checkout.load');
    } finally {
      await child.close();
      await root.close();
    }
  });
}
