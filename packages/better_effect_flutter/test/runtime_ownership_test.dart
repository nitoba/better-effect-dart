import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _OwnedResource {
  const _OwnedResource();
}

final class _CloseFailure implements Exception {
  const _CloseFailure();
}

void main() {
  Future<Runtime> countedRuntime(void Function() released) {
    return Module([
      .resource<_OwnedResource>(
        acquire: (_) async => const _OwnedResource(),
        release: (_, _) async {
          released();
        },
      ),
    ]).start();
  }

  testWidgets('external ownership never closes the Runtime', (tester) async {
    final first = await Module(const <Binding>[]).start();
    final second = await Module(const <Binding>[]).start();

    await tester.pumpWidget(
      BetterEffectProvider.value(runtime: first, child: const SizedBox()),
    );
    await tester.pumpWidget(
      BetterEffectProvider.value(runtime: second, child: const SizedBox()),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(first.isClosed, isFalse);
    expect(second.isClosed, isFalse);

    await first.close();
    await second.close();
  });

  testWidgets('widget ownership closes replacement and disposal exactly once', (
    tester,
  ) async {
    var firstReleases = 0;
    var secondReleases = 0;
    final first = await countedRuntime(() => firstReleases++);
    final second = await countedRuntime(() => secondReleases++);

    await tester.pumpWidget(
      BetterEffectProvider(
        runtime: first,
        ownership: BetterEffectRuntimeOwnership.widget,
        lifecyclePolicy: const BetterEffectLifecyclePolicy.widget(),
        child: const SizedBox(),
      ),
    );
    await tester.pumpWidget(
      BetterEffectProvider(
        runtime: second,
        ownership: BetterEffectRuntimeOwnership.widget,
        lifecyclePolicy: const BetterEffectLifecyclePolicy.widget(),
        child: const SizedBox(),
      ),
    );
    await tester.pump();

    expect(first.isClosed, isTrue);
    expect(firstReleases, 1);
    expect(second.isClosed, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(second.isClosed, isTrue);
    expect(secondReleases, 1);
  });

  testWidgets('widget ownership ignores application exit requests', (
    tester,
  ) async {
    final runtime = await Module(const <Binding>[]).start();

    await tester.pumpWidget(
      BetterEffectProvider(
        runtime: runtime,
        ownership: BetterEffectRuntimeOwnership.widget,
        lifecyclePolicy: const BetterEffectLifecyclePolicy.widget(),
        child: const Text('feature', textDirection: TextDirection.ltr),
      ),
    );

    await tester.binding.handleRequestAppExit();
    await tester.pump();

    expect(runtime.isClosed, isFalse);
    expect(find.text('feature'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(runtime.isClosed, isTrue);
  });

  testWidgets('application exit removes the Runtime before closing it', (
    tester,
  ) async {
    final runtime = await Module(const <Binding>[]).start();

    await tester.pumpWidget(
      BetterEffectProvider(
        runtime: runtime,
        child: const Text('application', textDirection: TextDirection.ltr),
      ),
    );

    final response = await tester.binding.handleRequestAppExit();
    await tester.pump();

    expect(response, AppExitResponse.exit);
    expect(runtime.isClosed, isTrue);
    expect(find.text('application'), findsNothing);
  });

  testWidgets('application close forwards cooperative interruption policy', (
    tester,
  ) async {
    final runtime = await Module(const <Binding>[]).start();
    final started = Completer<void>();
    final cancellationReason = Completer<Object?>();
    final running = runtime.runExit(
      Effect<Unit, Never>.result((use) async {
        started.complete();
        await use.cancellation.whenCancelled;
        cancellationReason.complete(use.cancellation.reason);
        use.cancellation.throwIfCancelled();
        return unit;
      }),
    );

    await started.future;
    await tester.pumpWidget(
      BetterEffectProvider(
        runtime: runtime,
        lifecyclePolicy: const BetterEffectLifecyclePolicy.application(
          gracePeriod: Duration(milliseconds: 1),
          interruptExecutionsBeforeClose: true,
        ),
        child: const SizedBox(),
      ),
    );

    // Disposal starts Runtime.close synchronously. Advancing the fake clock by
    // the configured grace period requests cancellation deterministically.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(await cancellationReason.future, 'runtime-shutdown');
    expect(await running, isA<ExitInterrupted<Unit, Never>>());
    await runtime.close();
    expect(runtime.isClosed, isTrue);
  });

  testWidgets('application exit and widget disposal do not double close', (
    tester,
  ) async {
    var releases = 0;
    final runtime = await countedRuntime(() => releases++);

    await tester.pumpWidget(
      BetterEffectProvider(runtime: runtime, child: const SizedBox()),
    );

    await tester.binding.handleRequestAppExit();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(releases, 1);
  });

  testWidgets('close error handler is best-effort', (tester) async {
    final reported = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() {
      FlutterError.onError = previousHandler;
    });

    final runtime = await Module([
      .resource<_OwnedResource>(
        acquire: (_) async => const _OwnedResource(),
        release: (_, _) => throw const _CloseFailure(),
      ),
    ]).start();

    await tester.pumpWidget(
      BetterEffectProvider(
        runtime: runtime,
        onRuntimeCloseError: (_, _) => throw StateError('handler failed'),
        child: const SizedBox(),
      ),
    );

    await tester.binding.handleRequestAppExit();
    await tester.pump();

    expect(runtime.isClosed, isTrue);
    expect(reported.any((details) => details.exception is StateError), isTrue);
  });

  testWidgets('bootstrap restarts when backendFactory changes', (tester) async {
    final module = Module(const <Binding>[]);
    final runtimes = <Runtime>[];
    var firstFactoryCalls = 0;
    var secondFactoryCalls = 0;

    ResolverBackend firstFactory() {
      firstFactoryCalls++;
      return AutoInjectorBackend();
    }

    ResolverBackend secondFactory() {
      secondFactoryCalls++;
      return AutoInjectorBackend();
    }

    Widget bootstrap(BetterEffectBackendFactory factory) {
      return BetterEffectBootstrap(
        module: module,
        backendFactory: factory,
        builder: (context) {
          final runtime = context.effectRuntime;
          if (runtimes.isEmpty || !identical(runtimes.last, runtime)) {
            runtimes.add(runtime);
          }
          return const SizedBox();
        },
      );
    }

    await tester.pumpWidget(bootstrap(firstFactory));
    await tester.pumpAndSettle();
    final firstRuntime = runtimes.single;

    await tester.pumpWidget(bootstrap(secondFactory));
    await tester.pumpAndSettle();

    expect(firstFactoryCalls, 1);
    expect(secondFactoryCalls, 1);
    expect(firstRuntime.isClosed, isTrue);
    expect(runtimes, hasLength(2));
    expect(identical(runtimes.first, runtimes.last), isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('stale bootstrap startup closes its acquired Runtime', (
    tester,
  ) async {
    final acquisitionStarted = Completer<void>();
    final continueAcquisition = Completer<void>();
    var releases = 0;

    final module = Module([
      .resource<_OwnedResource>(
        acquire: (_) async {
          acquisitionStarted.complete();
          await continueAcquisition.future;
          return const _OwnedResource();
        },
        release: (_, _) async {
          releases++;
        },
      ),
    ]);

    await tester.pumpWidget(
      BetterEffectBootstrap(module: module, builder: (_) => const SizedBox()),
    );
    await acquisitionStarted.future;

    await tester.pumpWidget(const SizedBox());
    continueAcquisition.complete();
    await tester.pumpAndSettle();

    expect(releases, 1);
  });
}
