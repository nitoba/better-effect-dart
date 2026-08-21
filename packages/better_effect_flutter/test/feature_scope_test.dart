import 'package:better_effect_flutter/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class ParentService {
  const ParentService(this.value);

  final String value;
}

final class FeatureService {
  const FeatureService(this.value);

  final String value;
}

final class _FeatureViewModel extends ChangeNotifier {
  _FeatureViewModel(this.commands, this.service);

  final EffectCommands commands;
  final FeatureService service;
}

void main() {
  testWidgets('feature exposes child services and disposal keeps parent open', (
    tester,
  ) async {
    final root = await Module([
      .instance<ParentService>(const ParentService('parent')),
    ]).start();
    Runtime? child;

    await tester.pumpWidget(
      BetterEffectTestApp(
        runtime: root,
        child: BetterEffectFeatureScope(
          module: Module([
            .instance<FeatureService>(const FeatureService('feature')),
          ]),
          label: 'checkout',
          loadingBuilder: (_) => const Text('loading'),
          builder: (context) {
            child = context.effectRuntime;
            return Text(
              '${context.readEffectService<ParentService>().value}:'
              '${context.readEffectService<FeatureService>().value}',
            );
          },
        ),
      ),
    );

    expect(find.text('loading'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('parent:feature'), findsOneWidget);
    expect(child?.parentRuntimeId, root.runtimeId);
    expect(child?.runtimeLabel, 'checkout');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(child?.state, RuntimeState.closed);
    expect(root.state, RuntimeState.active);
    await root.close();
  });

  testWidgets(
    'feature disposal interrupts an active child Command and keeps parent open',
    (tester) async {
      final root = await Module(const <Binding>[]).start();
      final started = TestSignal();
      Runtime? child;
      EffectCommand0<int, Never>? command;

      await tester.pumpWidget(
        BetterEffectTestApp(
          runtime: root,
          child: BetterEffectFeatureScope(
            module: Module(const <Binding>[]),
            builder: (context) {
              child = context.effectRuntime;
              command ??= context.effectCommands<int, Never>(
                () => Effect<int, Never>.result((use) async {
                  started.signal();
                  await use.cancellation.whenCancelled;
                  use.cancellation.throwIfCancelled();
                  return 1;
                }),
                debugLabel: 'feature.long-running',
              );
              return const Text('feature-ready');
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('feature-ready'), findsOneWidget);

      final result = command!.execute();
      await started.wait;
      expect(command?.isRunning, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      // Runtime.close uses a zero-duration grace timer before requesting
      // cooperative interruption. Advance flutter_test's fake clock so the
      // owned child can publish the interruption deterministically.
      await tester.pump(Duration.zero);

      expect(await result, isExitInterrupted<int, Never>());
      await tester.pumpAndSettle();
      expect(child?.state, RuntimeState.closed);
      expect(root.state, RuntimeState.active);

      command?.dispose();
      await root.close();
    },
  );

  testWidgets('startup failure can retry with a fresh child', (tester) async {
    var attempts = 0;
    final root = await Module(const <Binding>[]).start();
    final module = Module([
      .resource<FeatureService>(
        acquire: (_) async {
          attempts++;
          if (attempts == 1) throw StateError('first startup');
          return const FeatureService('ready');
        },
        release: (_, _) {},
      ),
    ]);

    await tester.pumpWidget(
      BetterEffectTestApp(
        runtime: root,
        child: BetterEffectFeatureScope(
          module: module,
          errorBuilder: (context, error, stackTrace, retry) {
            return GestureDetector(onTap: retry, child: const Text('retry'));
          },
          builder: (context) =>
              Text(context.readEffectService<FeatureService>().value),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('retry'), findsOneWidget);

    await tester.tap(find.text('retry'));
    await tester.pumpAndSettle();
    expect(find.text('ready'), findsOneWidget);
    expect(attempts, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await root.close();
  });

  testWidgets('restart replaces child and recreates ViewModel', (tester) async {
    final root = await Module(const <Binding>[]).start();
    var restartKey = 0;
    var created = 0;
    Runtime? firstRuntime;
    Runtime? latestRuntime;

    Widget buildTree() {
      final value = restartKey;
      return BetterEffectTestApp(
        runtime: root,
        child: BetterEffectFeatureScope(
          module: Module([
            .instance<FeatureService>(FeatureService('feature-$value')),
          ]),
          restartKey: value,
          builder: (context) {
            final runtime = context.effectRuntime;
            firstRuntime ??= runtime;
            latestRuntime = runtime;
            return EffectViewModelBuilder<_FeatureViewModel>(
              create: (context, commands) {
                created++;
                return _FeatureViewModel(
                  commands,
                  context.readEffectService<FeatureService>(),
                );
              },
              builder: (context, viewModel, child) {
                return Text(viewModel.service.value);
              },
            );
          },
        ),
      );
    }

    await tester.pumpWidget(buildTree());
    await tester.pumpAndSettle();
    expect(find.text('feature-0'), findsOneWidget);
    expect(created, 1);

    restartKey = 1;
    await tester.pumpWidget(buildTree());
    await tester.pumpAndSettle();
    expect(find.text('feature-1'), findsOneWidget);
    expect(created, 2);
    expect(firstRuntime?.state, RuntimeState.closed);
    expect(latestRuntime, isNot(same(firstRuntime)));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await root.close();
  });

  testWidgets(
    'observer changes keep the effective Runtime and ViewModel instance',
    (tester) async {
      final root = await Module(const <Binding>[]).start();
      final module = Module([
        .instance<FeatureService>(const FeatureService('feature')),
      ]);
      var created = 0;
      EffectCommandObserver observer = (_) {};
      Runtime? firstRuntime;
      Runtime? latestRuntime;
      EffectCommands? firstCommands;
      EffectCommands? latestCommands;

      Widget buildTree() {
        return BetterEffectTestApp(
          runtime: root,
          child: BetterEffectFeatureScope(
            module: module,
            observer: observer,
            builder: (context) {
              final runtime = context.effectRuntime;
              final commands = context.effectCommands;
              firstRuntime ??= runtime;
              firstCommands ??= commands;
              latestRuntime = runtime;
              latestCommands = commands;
              return EffectViewModelBuilder<_FeatureViewModel>(
                create: (context, commands) {
                  created++;
                  return _FeatureViewModel(
                    commands,
                    context.readEffectService<FeatureService>(),
                  );
                },
                builder: (context, viewModel, child) {
                  return Text('${viewModel.service.value}:$created');
                },
              );
            },
          ),
        );
      }

      await tester.pumpWidget(buildTree());
      await tester.pumpAndSettle();
      expect(find.text('feature:1'), findsOneWidget);
      expect(created, 1);

      observer = (_) {};
      await tester.pumpWidget(buildTree());
      await tester.pumpAndSettle();

      expect(created, 1);
      expect(latestRuntime, same(firstRuntime));
      expect(latestCommands, isNot(same(firstCommands)));
      expect(find.text('feature:1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await root.close();
    },
  );

  testWidgets('nested feature scopes inherit through the nearest child', (
    tester,
  ) async {
    final root = await Module([
      .instance<ParentService>(const ParentService('root')),
    ]).start();

    await tester.pumpWidget(
      BetterEffectTestApp(
        runtime: root,
        child: BetterEffectFeatureScope(
          module: Module([
            .instance<FeatureService>(const FeatureService('outer')),
          ]),
          label: 'outer',
          builder: (_) => BetterEffectFeatureScope(
            module: Module([.instance<int>(42)]),
            label: 'inner',
            builder: (context) {
              return Text(
                '${context.readEffectService<ParentService>().value}:'
                '${context.readEffectService<FeatureService>().value}:'
                '${context.readEffectService<int>()}:'
                '${context.effectRuntime.runtimeLabel}',
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('root:outer:42:inner'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await root.close();
  });
}
