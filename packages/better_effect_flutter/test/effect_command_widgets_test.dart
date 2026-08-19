import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class UiFailure implements Exception {
  const UiFailure(this.message);

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

  testWidgets('builder renders typed command states', (tester) async {
    final command = commands<int, UiFailure>(
      () => Effect<int, UiFailure>.succeed(3),
    );
    addTearDown(command.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: EffectCommandBuilder<int, UiFailure>(
          command: command,
          builder: (context, state, _) {
            return Text(switch (state) {
              EffectCommandIdle<int, UiFailure>() => 'idle',
              EffectCommandRunning<int, UiFailure>() => 'running',
              EffectCommandSuccess<int, UiFailure>(:final value) =>
                'success:$value',
              EffectCommandFailure<int, UiFailure>() => 'failure',
              EffectCommandDefect<int, UiFailure>() => 'defect',
              EffectCommandInterrupted<int, UiFailure>() => 'interrupted',
            });
          },
        ),
      ),
    );

    expect(find.text('idle'), findsOneWidget);

    await command.execute();
    await tester.pump();

    expect(find.text('success:3'), findsOneWidget);
  });

  testWidgets('listener consumes a success revision once', (tester) async {
    var successCalls = 0;
    final command = commands<int, UiFailure>(
      () => Effect<int, UiFailure>.succeed(1),
    );
    addTearDown(command.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: EffectCommandListener<int, UiFailure>(
          command: command,
          onSuccess: (context, value) => successCalls++,
          child: const SizedBox(),
        ),
      ),
    );

    await command.execute();
    await tester.pump();
    await tester.pump();
    expect(successCalls, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: EffectCommandListener<int, UiFailure>(
          command: command,
          onSuccess: (context, value) => successCalls++,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pump();

    expect(successCalls, 1);
  });

  testWidgets('failure listener receives typed error and previous data', (
    tester,
  ) async {
    const failure = UiFailure('nope');
    UiFailure? received;
    int? previous;
    var shouldFail = false;

    final command = commands<int, UiFailure>(
      () => shouldFail
          ? Effect<int, UiFailure>.fail(failure)
          : Effect<int, UiFailure>.succeed(8),
    );
    addTearDown(command.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: EffectCommandListener<int, UiFailure>(
          command: command,
          onFailure: (context, error, retained) {
            received = error;
            previous = retained;
          },
          child: const SizedBox(),
        ),
      ),
    );

    await command.execute();
    await tester.pump();
    shouldFail = true;
    await command.execute();
    await tester.pump();
    await tester.pump();

    expect(received, same(failure));
    expect(previous, 8);
  });

  testWidgets('provider exposes commands without a global injector', (
    tester,
  ) async {
    EffectCommands? scopedCommands;

    await tester.pumpWidget(
      BetterEffectProvider.value(
        runtime: runtime,
        child: Builder(
          builder: (context) {
            scopedCommands = context.effectCommands;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(scopedCommands, isNotNull);
  });
}
