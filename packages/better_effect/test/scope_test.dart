import 'dart:async';

import 'package:better_effect/better_effect.dart';
import 'package:test/test.dart';

final class Resource {
  const Resource(this.name);

  final String name;
}

void main() {
  test('module resources are released in reverse acquisition order', () async {
    final events = <String>[];

    final module = Module([
      .resource<Resource>(
        acquire: (_) async {
          events.add('acquire:first');
          return const Resource('first');
        },
        release: (resource) async {
          events.add('release:${resource.name}');
        },
        key: const ServiceKey<Resource>('first'),
      ),
      .resource<Resource>(
        acquire: (_) async {
          events.add('acquire:second');
          return const Resource('second');
        },
        release: (resource) async {
          events.add('release:${resource.name}');
        },
        key: const ServiceKey<Resource>('second'),
      ),
    ]);

    final result = await module.run(Effect<Unit, Never>.succeed(unit));

    expect(result.isSuccess(), isTrue);
    expect(events, [
      'acquire:first',
      'acquire:second',
      'release:second',
      'release:first',
    ]);
  });

  test('use.acquire releases execution resources after runtime.run', () async {
    var released = false;

    final runtime = await Module(const <Binding>[]).start();

    try {
      final effect = Effect<String, Never>.result((use) async {
        final resource = await use.acquire(
          Effect<Resource, Never>.succeed(const Resource('execution')),
          release: (_) async {
            released = true;
          },
        );

        return resource.name;
      });

      final result = await runtime.run(effect);

      expect(result.getOrNull(), 'execution');
      expect(released, isTrue);
    } finally {
      await runtime.close();
    }
  });

  test(
    'Runtime.close drains active executions before module resources',
    () async {
      final events = <String>[];
      final started = Completer<void>();
      final continueExecution = Completer<void>();

      final module = Module([
        .resource<Resource>(
          acquire: (_) async {
            events.add('acquire:runtime');
            return const Resource('runtime');
          },
          release: (_) async {
            events.add('release:runtime');
          },
        ),
      ]);
      final runtime = await module.start();

      final running = runtime.runExit(
        Effect<Resource, Never>.result((use) async {
          use<Resource>();
          started.complete();
          await continueExecution.future;
          events.add('resolve:after-closing');
          await use.acquire(
            Effect<Resource, Never>.succeed(const Resource('execution')),
            release: (_) async {
              events.add('release:execution');
            },
          );
          events.add('acquire:after-closing');
          return use<Resource>();
        }),
      );

      await started.future;

      final closing = runtime.close();

      expect(runtime.state, RuntimeState.closing);
      expect(runtime.isClosed, isTrue);
      expect(events, ['acquire:runtime']);
      expect(() => runtime.services, throwsA(isA<RuntimeClosedException>()));

      await expectLater(
        runtime.run(Effect<Unit, Never>.succeed(unit)),
        throwsA(isA<RuntimeClosedException>()),
      );

      continueExecution.complete();

      final exit = await running;
      await closing;

      expect(exit, isA<ExitSuccess<Resource, Never>>());
      expect(runtime.state, RuntimeState.closed);
      expect(events, [
        'acquire:runtime',
        'resolve:after-closing',
        'acquire:after-closing',
        'release:execution',
        'release:runtime',
      ]);
    },
  );

  test(
    'execution resources close before module resources during shutdown',
    () async {
      final events = <String>[];
      final acquired = Completer<void>();
      final continueExecution = Completer<void>();

      final module = Module([
        .resource<Resource>(
          acquire: (_) async {
            events.add('acquire:runtime');
            return const Resource('runtime');
          },
          release: (_) async {
            events.add('release:runtime');
          },
        ),
      ]);
      final runtime = await module.start();

      final running = runtime.run(
        Effect<Unit, Never>.result((use) async {
          await use.acquire(
            Effect<Resource, Never>.succeed(const Resource('execution')),
            release: (_) async {
              events.add('release:execution');
            },
          );
          acquired.complete();
          await continueExecution.future;
          return unit;
        }),
      );

      await acquired.future;
      final closing = runtime.close();

      expect(events, ['acquire:runtime']);

      continueExecution.complete();
      await running;
      await closing;

      expect(events, [
        'acquire:runtime',
        'release:execution',
        'release:runtime',
      ]);
    },
  );

  test(
    'Runtime.close requests cooperative cancellation after the grace period',
    () async {
      final started = Completer<void>();
      var cancellationObserved = false;

      final runtime = await Module(const <Binding>[]).start();
      final running = runtime.run(
        Effect<Unit, Never>.result((use) async {
          started.complete();
          await use.cancellation.whenCancelled;
          cancellationObserved = use.cancellation.isCancelled;
          return unit;
        }),
      );

      await started.future;
      await runtime.close(
        gracePeriod: Duration.zero,
        interruptAfterGracePeriod: true,
      );

      await running;
      expect(cancellationObserved, isTrue);
      expect(runtime.state, RuntimeState.closed);
    },
  );

  test('concurrent Runtime.close calls share the active shutdown', () async {
    final started = Completer<void>();
    final continueExecution = Completer<void>();
    final runtime = await Module(const <Binding>[]).start();

    final running = runtime.run(
      Effect<Unit, Never>.result((use) async {
        started.complete();
        await continueExecution.future;
        return unit;
      }),
    );

    await started.future;
    final firstClose = runtime.close();
    final secondClose = runtime.close();

    expect(identical(firstClose, secondClose), isTrue);

    continueExecution.complete();
    await running;
    await firstClose;
  });

  test('EffectLocal values are inherited and locally overridden', () async {
    const requestId = EffectLocal<String>('default', name: 'requestId');

    final effect = Effect<String, Never>.result((use) async {
      return use.local(requestId);
    });

    final module = Module(const <Binding>[]);

    final defaultResult = await module.run(effect);
    final localResult = await module.run(
      effect.withLocal(requestId, 'request-123'),
    );

    expect(defaultResult.getOrNull(), 'default');
    expect(localResult.getOrNull(), 'request-123');
  });

  test('Effect.provide overrides one service only for that Effect', () async {
    final module = Module([.instance<String>('live')]);

    final effect = Effect<String, Never>.result((use) async {
      return use<String>();
    });

    final liveResult = await module.run(effect);
    final testResult = await module.run(effect.provide<String>('test'));

    expect(liveResult.getOrNull(), 'live');
    expect(testResult.getOrNull(), 'test');
  });
}
