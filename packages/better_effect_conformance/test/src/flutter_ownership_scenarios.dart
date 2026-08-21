import 'package:better_effect_flutter/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'registry.dart';

final class _OwnedResource {
  const _OwnedResource();
}

final class _ParentService {
  const _ParentService(this.value);

  final String value;
}

final class _FeatureService {
  const _FeatureService(this.value);

  final String value;
}

void registerFlutterOwnershipScenarios() {
  conformanceWidgetTest('OWNERSHIP-01', (tester) async {
    final runtime = await Module(const <Binding>[]).start();

    await tester.pumpWidget(
      BetterEffectProvider.value(runtime: runtime, child: const SizedBox()),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(runtime.state, RuntimeState.active);
    await runtime.close();
  });

  conformanceWidgetTest('OWNERSHIP-02', (tester) async {
    var releases = 0;
    final runtime = await Module([
      .resource<_OwnedResource>(
        acquire: (_) async => const _OwnedResource(),
        release: (_, _) {
          releases++;
        },
      ),
    ]).start();

    await tester.pumpWidget(
      BetterEffectProvider(
        runtime: runtime,
        ownership: BetterEffectRuntimeOwnership.widget,
        lifecyclePolicy: const BetterEffectLifecyclePolicy.widget(),
        child: const SizedBox(),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump();

    expect(runtime.state, RuntimeState.closed);
    expect(releases, 1);
  });

  conformanceWidgetTest('OWNERSHIP-03', (tester) async {
    final acquisitionStarted = TestSignal();
    final continueAcquisition = TestSignal();
    var releases = 0;
    final module = Module([
      .resource<_OwnedResource>(
        acquire: (_) async {
          acquisitionStarted.signal();
          await continueAcquisition.wait;
          return const _OwnedResource();
        },
        release: (_, _) {
          releases++;
        },
      ),
    ]);

    await tester.pumpWidget(
      BetterEffectBootstrap(module: module, builder: (_) => const SizedBox()),
    );
    await acquisitionStarted.wait;

    await tester.pumpWidget(const SizedBox());
    continueAcquisition.signal();
    await tester.pumpAndSettle();

    expect(releases, 1);
  });

  conformanceWidgetTest('OWNERSHIP-04', (tester) async {
    final root = await Module([
      .instance<_ParentService>(const _ParentService('parent')),
    ]).start();
    Runtime? child;

    await tester.pumpWidget(
      BetterEffectTestApp(
        runtime: root,
        child: BetterEffectFeatureScope(
          module: Module([
            .instance<_FeatureService>(const _FeatureService('feature')),
          ]),
          builder: (context) {
            child = context.effectRuntime;
            return Text(
              '${context.readEffectService<_ParentService>().value}:'
              '${context.readEffectService<_FeatureService>().value}',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('parent:feature'), findsOneWidget);
    expect(child?.parentRuntimeId, root.runtimeId);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(child?.state, RuntimeState.closed);
    expect(root.state, RuntimeState.active);
    await root.close();
  });
}
