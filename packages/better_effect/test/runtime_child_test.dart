import 'package:better_effect/testing.dart';
import 'package:test/test.dart';

final class ParentOnly {
  const ParentOnly(this.value);
  final String value;
}

final class SharedValue {
  const SharedValue(this.value);
  final String value;
}

final class FeatureRepository {
  const FeatureRepository(this.parent, this.shared);
  final ParentOnly parent;
  final SharedValue shared;
}

final class FeatureResource {
  const FeatureResource(this.id);
  final int id;
}

void main() {
  test('child shadows locally and falls back to parent services', () async {
    final root = await Module([
      .instance<ParentOnly>(const ParentOnly('root-only')),
      .instance<SharedValue>(const SharedValue('root')),
    ]).start();
    final child = await root.fork(
      Module([
        .instance<SharedValue>(const SharedValue('feature')),
        .provide<FeatureRepository>(FeatureRepository.new),
      ]),
      label: 'checkout',
    );

    try {
      final values = await child.runExit(
        Effect<(String, String), Never>.result((use) async {
          final repository = use<FeatureRepository>();
          return (repository.parent.value, repository.shared.value);
        }),
      );
      expect(expectExitSuccess(values), ('root-only', 'feature'));
      expect(root.services<SharedValue>().value, 'root');
      expect(child.runtimeLabel, 'checkout');
      expect(child.parentRuntimeId, root.runtimeId);
      expect(child.isChildRuntime, isTrue);
      expect(root.isChildRuntime, isFalse);
    } finally {
      await child.close();
      await root.close();
    }
  });

  test('feature resource survives executions and closes once', () async {
    var acquisitions = 0;
    var releases = 0;
    final root = await Module(const <Binding>[]).start();
    final child = await root.fork(
      Module([
        .resource<FeatureResource>(
          acquire: (_) async => FeatureResource(++acquisitions),
          release: (_, _) {
            releases++;
          },
        ),
      ]),
    );

    final first = await child.runExit(
      Effect<int, Never>.result((use) async => use<FeatureResource>().id),
    );
    final second = await child.runExit(
      Effect<int, Never>.result((use) async => use<FeatureResource>().id),
    );

    expect(expectExitSuccess(first), 1);
    expect(expectExitSuccess(second), 1);
    expect(acquisitions, 1);
    expect(releases, 0);

    await child.close();
    await child.close();
    expect(releases, 1);
    expect(root.state, RuntimeState.active);
    await root.close();
  });

  test(
    'siblings isolate local resources and parent survives child close',
    () async {
      final root = await Module([
        .instance<ParentOnly>(const ParentOnly('parent')),
      ]).start();
      final first = await root.fork(
        Module([.instance<SharedValue>(const SharedValue('one'))]),
      );
      final second = await root.fork(
        Module([.instance<SharedValue>(const SharedValue('two'))]),
      );

      expect(first.services<SharedValue>().value, 'one');
      expect(second.services<SharedValue>().value, 'two');
      expect(first.services<ParentOnly>().value, 'parent');
      expect(second.services<ParentOnly>().value, 'parent');

      await first.close();
      expect(root.state, RuntimeState.active);
      expect(second.services<SharedValue>().value, 'two');

      await second.close();
      await root.close();
    },
  );

  test('Runtime identities are unique across roots and siblings', () async {
    final firstRoot = await Module(const <Binding>[]).start();
    final secondRoot = await Module(const <Binding>[]).start();
    final firstChild = await firstRoot.fork(Module(const <Binding>[]));
    final secondChild = await firstRoot.fork(Module(const <Binding>[]));

    final ids = <int>{
      firstRoot.runtimeId,
      secondRoot.runtimeId,
      firstChild.runtimeId,
      secondChild.runtimeId,
    };

    expect(ids, hasLength(4));
    expect(firstChild.parentRuntimeId, firstRoot.runtimeId);
    expect(secondChild.parentRuntimeId, firstRoot.runtimeId);

    await firstRoot.close();
    await secondRoot.close();
  });

  test(
    'parent and child close safely when shutdown races with active work',
    () async {
      final root = await Module(const <Binding>[]).start();
      final child = await root.fork(Module(const <Binding>[]));
      final started = TestSignal();
      final execution = child.execute(
        Effect<int, Never>.result((use) async {
          started.signal();
          await use.cancellation.whenCancelled;
          use.cancellation.throwIfCancelled();
          return 1;
        }),
      );

      await started.wait;
      final parentClose = root.close(interruptAfterGracePeriod: true);
      final childClose = child.close(interruptAfterGracePeriod: true);

      await Future.wait<void>([parentClose, childClose]);

      expect(await execution.exit, isExitInterrupted<int, Never>());
      expect(child.state, RuntimeState.closed);
      expect(root.state, RuntimeState.closed);
    },
  );

  test(
    'parent closes active child before releasing parent resources',
    () async {
      final events = TestEventRecorder<String>();
      final started = TestSignal();
      final root = await Module([
        .resource<ParentOnly>(
          acquire: (_) async {
            events.record('parent-acquire');
            return const ParentOnly('parent');
          },
          release: (_, _) {
            events.record('parent-release');
          },
        ),
      ]).start();
      final child = await root.fork(
        Module([
          .resource<FeatureResource>(
            acquire: (_) async {
              events.record('child-acquire');
              return const FeatureResource(1);
            },
            release: (_, _) {
              events.record('child-release');
            },
          ),
        ]),
      );
      final execution = child.execute(
        Effect<int, Never>.result((use) async {
          use<FeatureResource>();
          started.signal();
          await use.cancellation.whenCancelled;
          use.cancellation.throwIfCancelled();
          return 1;
        }),
      );

      await started.wait;
      await root.close(interruptAfterGracePeriod: true);

      expect(await execution.exit, isExitInterrupted<int, Never>());
      events.expectEvents(const <String>[
        'parent-acquire',
        'child-acquire',
        'child-release',
        'parent-release',
      ]);
      expect(child.state, RuntimeState.closed);
      expect(root.state, RuntimeState.closed);
    },
  );

  test('partial child startup failure releases acquired resources', () async {
    var releases = 0;
    final root = await Module(const <Binding>[]).start();

    await expectLater(
      root.fork(
        Module([
          .resource<FeatureResource>(
            acquire: (_) async => const FeatureResource(1),
            release: (_, _) {
              releases++;
            },
          ),
          .resource<ParentOnly>(
            acquire: (_) async => throw StateError('startup failed'),
            release: (_, _) {},
          ),
        ]),
      ),
      throwsA(isA<ResourceAcquisitionException>()),
    );

    expect(releases, 1);
    expect(root.state, RuntimeState.active);
    await root.close();
  });

  test('closing parent rejects new children', () async {
    final root = await Module(const <Binding>[]).start();
    await root.close();

    await expectLater(
      root.fork(Module(const <Binding>[])),
      throwsA(isA<RuntimeClosedException>()),
    );
  });

  test(
    'execution-scoped Modules inside child fall back through both layers',
    () async {
      final root = await Module([
        .instance<ParentOnly>(const ParentOnly('parent')),
      ]).start();
      final child = await root.fork(
        Module([.instance<SharedValue>(const SharedValue('child'))]),
      );

      try {
        final exit = await child.runExitWith(
          Module([.instance<int>(42)]),
          Effect<(String, String, int), Never>.result((use) async {
            return (
              use<ParentOnly>().value,
              use<SharedValue>().value,
              use<int>(),
            );
          }),
        );
        expect(expectExitSuccess(exit), ('parent', 'child', 42));
      } finally {
        await child.close();
        await root.close();
      }
    },
  );
}
