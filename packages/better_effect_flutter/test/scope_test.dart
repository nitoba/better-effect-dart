import 'dart:async';

import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _BootstrapResource {
  const _BootstrapResource();
}

void main() {
  testWidgets('owned provider closes its Runtime when removed', (tester) async {
    final runtime = await Module(const <Binding>[]).start();

    await tester.pumpWidget(
      BetterEffectProvider(runtime: runtime, child: const SizedBox()),
    );

    expect(runtime.isClosed, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(runtime.isClosed, isTrue);
  });

  testWidgets('value provider leaves Runtime ownership to its caller', (
    tester,
  ) async {
    final runtime = await Module(const <Binding>[]).start();

    await tester.pumpWidget(
      BetterEffectProvider.value(runtime: runtime, child: const SizedBox()),
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(runtime.isClosed, isFalse);
    await runtime.close();
  });

  testWidgets('bootstrap starts a Module and exposes the Runtime', (
    tester,
  ) async {
    final startGate = Completer<_BootstrapResource>();
    Runtime? scopedRuntime;

    final module = Module([
      .resource<_BootstrapResource>(
        acquire: (_) => startGate.future,
        release: (_) {},
      ),
    ]);

    await tester.pumpWidget(
      BetterEffectBootstrap(
        module: module,
        loadingBuilder: (_) =>
            const Text('loading', textDirection: TextDirection.ltr),
        builder: (context) {
          scopedRuntime = context.effectRuntime;
          return const Text('ready', textDirection: TextDirection.ltr);
        },
      ),
    );

    expect(find.text('loading'), findsOneWidget);

    startGate.complete(const _BootstrapResource());
    await tester.pumpAndSettle();

    expect(find.text('ready'), findsOneWidget);
    expect(scopedRuntime, isNotNull);
    expect(scopedRuntime!.isClosed, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(scopedRuntime!.isClosed, isTrue);
  });
}
