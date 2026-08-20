import 'package:better_effect_flutter/testing.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class SelectorFailure implements Exception {
  const SelectorFailure(this.message);

  final String message;
}

Widget _host(Widget child) {
  return Directionality(textDirection: TextDirection.ltr, child: child);
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

  testWidgets('selector rebuilds only when selected value changes', (
    tester,
  ) async {
    final gate = TestGate<int>();
    final command = commands<int, SelectorFailure>(
      () => Effect<int, SelectorFailure>.result((_) => gate.future),
    );
    addTearDown(command.dispose);
    final builds = <bool>[];

    await tester.pumpWidget(
      _host(
        EffectCommandSelector<int, SelectorFailure, bool>(
          command: command,
          selector: (state) => state.isRunning,
          builder: (context, isRunning, child) {
            builds.add(isRunning);
            return Text('$isRunning');
          },
        ),
      ),
    );

    final running = command.execute();
    await tester.pump();
    gate.complete(42);
    await running;
    await tester.pump();

    expect(builds, <bool>[false, true, false]);
  });

  testWidgets('custom equality suppresses equivalent list values', (
    tester,
  ) async {
    final command = commands.withInput<int, List<int>, SelectorFailure>(
      (input) => Effect<List<int>, SelectorFailure>.succeed(<int>[input]),
    );
    addTearDown(command.dispose);
    final builds = <List<int>?>[];

    await tester.pumpWidget(
      _host(
        EffectCommandSelector<List<int>, SelectorFailure, List<int>?>(
          command: command,
          selector: (state) => state.dataOrNull,
          equals: listEquals,
          builder: (context, selected, child) {
            builds.add(selected);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await command.execute(1);
    await tester.pump();
    await command.execute(1);
    await tester.pump();

    expect(builds, hasLength(2));
    expect(builds.last, <int>[1]);
  });

  testWidgets('nullable selections remain strongly typed', (tester) async {
    final command = commands.withInput<bool, int, SelectorFailure>(
      (fail) => fail
          ? Effect<int, SelectorFailure>.fail(const SelectorFailure('expected'))
          : Effect<int, SelectorFailure>.succeed(1),
    );
    addTearDown(command.dispose);
    final messages = <String?>[];

    await tester.pumpWidget(
      _host(
        EffectCommandSelector<int, SelectorFailure, String?>(
          command: command,
          selector: (state) => state.errorOrNull?.message,
          builder: (context, selected, child) {
            messages.add(selected);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await command.execute(false);
    await tester.pump();
    await command.execute(true);
    await tester.pump();

    expect(messages, <String?>[null, 'expected']);
  });

  testWidgets('command replacement detaches the old subscription', (
    tester,
  ) async {
    final first = commands<int, SelectorFailure>(
      () => Effect<int, SelectorFailure>.succeed(1),
    );
    final secondGate = TestGate<int>();
    final second = commands<int, SelectorFailure>(
      () => Effect<int, SelectorFailure>.result((_) => secondGate.future),
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final builds = <bool>[];
    const key = ValueKey<String>('selector');

    Widget build(EffectCommandBase<int, SelectorFailure> command) {
      return _host(
        EffectCommandSelector<int, SelectorFailure, bool>(
          key: key,
          command: command,
          selector: (state) => state.isRunning,
          builder: (context, selected, child) {
            builds.add(selected);
            return const SizedBox.shrink();
          },
        ),
      );
    }

    await tester.pumpWidget(build(first));
    await tester.pumpWidget(build(second));
    final afterReplacement = builds.length;

    await first.execute();
    await tester.pump();
    expect(builds, hasLength(afterReplacement));

    final running = second.execute();
    await tester.pump();
    expect(builds.last, isTrue);
    secondGate.complete(2);
    await running;
  });

  testWidgets('selector reuses the provided child', (tester) async {
    final gate = TestGate<int>();
    final command = commands<int, SelectorFailure>(
      () => Effect<int, SelectorFailure>.result((_) => gate.future),
    );
    addTearDown(command.dispose);
    const child = SizedBox(key: ValueKey<String>('stable-child'));
    final identities = <bool>[];

    await tester.pumpWidget(
      _host(
        EffectCommandSelector<int, SelectorFailure, bool>(
          command: command,
          selector: (state) => state.isRunning,
          child: child,
          builder: (context, selected, selectedChild) {
            identities.add(identical(selectedChild, child));
            return selectedChild!;
          },
        ),
      ),
    );

    final running = command.execute();
    await tester.pump();
    gate.complete(1);
    await running;
    await tester.pump();

    expect(identities, everyElement(isTrue));
    expect(find.byKey(child.key!), findsOneWidget);
  });

  testWidgets('buildWhen filters rendering transitions', (tester) async {
    final gates = <int, TestGate<int>>{1: TestGate<int>(), 2: TestGate<int>()};
    final command = commands.withInput<int, int, SelectorFailure>(
      (input) =>
          Effect<int, SelectorFailure>.result((_) => gates[input]!.future),
    );
    addTearDown(command.dispose);
    final builtData = <int?>[];

    await tester.pumpWidget(
      _host(
        EffectCommandBuilder<int, SelectorFailure>(
          command: command,
          buildWhen: (previous, current) {
            return previous.dataOrNull != current.dataOrNull;
          },
          builder: (context, state, child) {
            builtData.add(state.dataOrNull);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final first = command.execute(1);
    await tester.pump();
    expect(builtData, <int?>[null]);
    gates[1]!.complete(1);
    await first;
    await tester.pump();

    final second = command.execute(2);
    await tester.pump();
    expect(builtData, <int?>[null, 1]);
    gates[2]!.complete(2);
    await second;
    await tester.pump();

    expect(builtData, <int?>[null, 1, 2]);
  });

  testWidgets('selector exceptions surface through Flutter build', (
    tester,
  ) async {
    final command = commands<int, SelectorFailure>(
      () => Effect<int, SelectorFailure>.succeed(1),
    );
    addTearDown(command.dispose);

    await tester.pumpWidget(
      _host(
        EffectCommandSelector<int, SelectorFailure, bool>(
          command: command,
          selector: (_) => throw StateError('selector failed'),
          builder: (context, selected, child) {
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(tester.takeException(), isA<StateError>());
  });

  testWidgets('listener delivery remains independent from selector', (
    tester,
  ) async {
    final gate = TestGate<int>();
    final command = commands<int, SelectorFailure>(
      () => Effect<int, SelectorFailure>.result((_) => gate.future),
    );
    addTearDown(command.dispose);
    var successes = 0;
    final selections = <bool>[];

    await tester.pumpWidget(
      _host(
        EffectCommandListener<int, SelectorFailure>(
          command: command,
          onSuccess: (context, value) => successes++,
          child: EffectCommandSelector<int, SelectorFailure, bool>(
            command: command,
            selector: (state) => state.isRunning,
            builder: (context, selected, child) {
              selections.add(selected);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final running = command.execute();
    await tester.pump();
    gate.complete(1);
    await running;
    await tester.pump();
    await tester.pump();

    expect(successes, 1);
    expect(selections, <bool>[false, true, false]);
  });

  testWidgets('reset retention and clear use selected equality', (
    tester,
  ) async {
    final command = commands<int, SelectorFailure>(
      () => Effect<int, SelectorFailure>.succeed(7),
    );
    addTearDown(command.dispose);
    final data = <int?>[];

    await tester.pumpWidget(
      _host(
        EffectCommandSelector<int, SelectorFailure, int?>(
          command: command,
          selector: (state) => state.dataOrNull,
          builder: (context, selected, child) {
            data.add(selected);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await command.execute();
    await tester.pump();
    expect(command.reset(), isTrue);
    await tester.pump();
    expect(command.clear(), isTrue);
    await tester.pump();

    expect(data, <int?>[null, 7, null]);
  });

  testWidgets('snapshot selector observes pending and queue counts', (
    tester,
  ) async {
    final firstGate = TestGate<int>();
    final secondGate = TestGate<int>();
    final command = commands.withInput<int, int, SelectorFailure>(
      (input) => Effect<int, SelectorFailure>.result(
        (_) => input == 1 ? firstGate.future : secondGate.future,
      ),
      policy: const CommandPolicy.queue(),
    );
    addTearDown(command.dispose);
    final counts = <({int pending, int queued})>[];

    await tester.pumpWidget(
      _host(
        EffectCommandSelector<
          int,
          SelectorFailure,
          ({int pending, int queued})
        >.snapshot(
          command: command,
          selector: (snapshot) =>
              (pending: snapshot.pendingCount, queued: snapshot.queuedCount),
          builder: (context, selected, child) {
            counts.add(selected);
            return Text('${selected.pending}:${selected.queued}');
          },
        ),
      ),
    );

    final first = command.execute(1);
    await tester.pump();
    expect(counts.last, (pending: 1, queued: 0));

    final second = command.execute(2);
    await tester.pump();
    expect(counts.last, (pending: 2, queued: 1));

    firstGate.complete(1);
    await first;
    await tester.pump();
    expect(counts.last, (pending: 1, queued: 0));

    secondGate.complete(2);
    await second;
    await tester.pump();
    expect(counts.last, (pending: 0, queued: 0));
  });
}
