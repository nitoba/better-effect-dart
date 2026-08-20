import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

final class ObserverCommandFailure implements Exception {
  const ObserverCommandFailure();
}

final class _CommandRuntimeObserver extends RuntimeObserver {
  final starts = <ExecutionStartEvent>[];
  final ends = <ExecutionEndEvent>[];

  @override
  void onExecutionStart(ExecutionStartEvent event) => starts.add(event);

  @override
  void onExecutionEnd(ExecutionEndEvent event) => ends.add(event);
}

void main() {
  test('EffectCommand debugLabel is forwarded to Runtime observers', () async {
    final observer = _CommandRuntimeObserver();
    final runtime = await Module(
      const <Binding>[],
    ).start(observers: <RuntimeObserver>[observer]);
    final commands = EffectCommands(runtime);
    final command = commands<int, ObserverCommandFailure>(
      () => Effect<int, ObserverCommandFailure>.succeed(42),
      debugLabel: 'users.load',
    );

    try {
      final exit = await command.execute();
      expect(exit, isA<ExitSuccess<int, ObserverCommandFailure>>());
      expect(observer.starts, hasLength(1));
      expect(observer.ends, hasLength(1));
      expect(observer.starts.single.context.executionLabel, 'users.load');
      expect(observer.ends.single.context.executionLabel, 'users.load');
      expect(
        observer.ends.single.context.executionId,
        observer.starts.single.context.executionId,
      );
    } finally {
      command.dispose();
      await runtime.close();
    }
  });
}
