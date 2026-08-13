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
