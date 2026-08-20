import 'package:better_effect_flutter/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class FlutterTestFailure implements Exception {
  const FlutterTestFailure(this.message);

  final String message;
}

void main() {
  test('typed Command assertions return the expected payloads', () async {
    final runtime = await Module(const <Binding>[]).start();
    final commands = EffectCommands(runtime);
    final success = commands<int, FlutterTestFailure>(
      () => Effect<int, FlutterTestFailure>.succeed(42),
    );
    final failure = commands<int, FlutterTestFailure>(
      () => Effect<int, FlutterTestFailure>.fail(
        const FlutterTestFailure('expected'),
      ),
    );
    final defect = commands<int, FlutterTestFailure>(
      () => Effect<int, FlutterTestFailure>.sync(
        () => throw StateError('defect'),
      ),
    );

    try {
      expectCommandIdle(success.value);
      await success.execute();
      expect(expectCommandSuccess(success.value), 42);

      await failure.execute();
      expect(expectCommandFailure(failure.value).message, 'expected');

      await defect.execute();
      expect(expectCommandDefect(defect.value).defect, isA<StateError>());

      expect(
        () => expectCommandFailure(success.value),
        throwsA(isA<EffectCommandTestExpectationException>()),
      );
    } finally {
      success.dispose();
      failure.dispose();
      defect.dispose();
      await runtime.close();
    }
  });

  testWidgets('BetterEffectTestApp leaves Runtime ownership to the test', (
    tester,
  ) async {
    final runtime = await Module(const <Binding>[]).start();

    await tester.pumpWidget(
      BetterEffectTestApp(runtime: runtime, child: const Text('ready')),
    );
    expect(find.text('ready'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(runtime.state, RuntimeState.active);

    await runtime.close();
    expect(runtime.state, RuntimeState.closed);
  });

  testWidgets('listener probe verifies one delivery per visible revision', (
    tester,
  ) async {
    final runtime = await Module(const <Binding>[]).start();
    final commands = EffectCommands(runtime);
    final gate = TestGate<int>();
    final command = commands<int, FlutterTestFailure>(
      () => Effect<int, FlutterTestFailure>.result((_) => gate.future),
    );
    final listener = EffectCommandListenerProbe<int, FlutterTestFailure>();

    try {
      await tester.pumpWidget(
        BetterEffectTestApp(
          runtime: runtime,
          child: EffectCommandListener<int, FlutterTestFailure>(
            command: command,
            onChanged: listener.call,
            child: const SizedBox.shrink(),
          ),
        ),
      );

      final running = command.execute();
      await tester.pump();
      expect(
        listener.deliveriesOf<EffectCommandRunning<int, FlutterTestFailure>>(),
        hasLength(1),
      );

      gate.complete(42);
      await running;
      await tester.pump();

      expect(
        listener.deliveriesOf<EffectCommandSuccess<int, FlutterTestFailure>>(),
        hasLength(1),
      );
      listener.expectUniqueRevisions();
    } finally {
      command.dispose();
      await runtime.close();
    }
  });
}
