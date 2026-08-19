import 'package:better_effect/better_effect.dart';
import 'package:test/test.dart';

abstract interface class Database {}

final class RuntimeResource {
  const RuntimeResource(this.name);

  final String name;
}

void main() {
  group('Module.overrideWith ordering', () {
    test('preserves resource positions when override order differs', () async {
      const first = ServiceKey<RuntimeResource>('first');
      const second = ServiceKey<RuntimeResource>('second');
      const third = ServiceKey<RuntimeResource>('third');
      final events = <String>[];

      Binding resource(String name, ServiceKey<RuntimeResource> key) {
        return Binding.resource<RuntimeResource>(
          key: key,
          acquire: (_) async {
            events.add('acquire:$name');
            return RuntimeResource(name);
          },
          release: (_, _) async {
            events.add('release:$name');
          },
        );
      }

      final base = Module([
        resource('first:live', first),
        resource('second:live', second),
        resource('third:live', third),
      ]);
      final overridden = base.overrideWith([
        resource('third:test', third),
        resource('first:test', first),
      ]);

      final runtime = await overridden.start();
      await runtime.close();

      expect(events, [
        'acquire:first:test',
        'acquire:second:live',
        'acquire:third:test',
        'release:third:test',
        'release:second:live',
        'release:first:test',
      ]);
    });

    test('appends new override identities in declaration order', () async {
      const existing = ServiceKey<RuntimeResource>('existing');
      const secondNew = ServiceKey<RuntimeResource>('second-new');
      const firstNew = ServiceKey<RuntimeResource>('first-new');
      final events = <String>[];

      Binding resource(String name, ServiceKey<RuntimeResource> key) {
        return Binding.resource<RuntimeResource>(
          key: key,
          acquire: (_) async {
            events.add('acquire:$name');
            return RuntimeResource(name);
          },
          release: (_, _) async {
            events.add('release:$name');
          },
        );
      }

      final module = Module([resource('existing', existing)]).overrideWith([
        resource('second-new', secondNew),
        resource('first-new', firstNew),
      ]);

      final runtime = await module.start();
      await runtime.close();

      expect(events, [
        'acquire:existing',
        'acquire:second-new',
        'acquire:first-new',
        'release:first-new',
        'release:second-new',
        'release:existing',
      ]);
    });
  });

  test('resource startup errors identify the failing resource', () async {
    final module = Module([
      .resource<RuntimeResource>(
        acquire: (services) async {
          services<Database>();
          return const RuntimeResource('unreachable');
        },
        release: (_, _) async {},
      ),
    ]);

    await expectLater(
      module.start(),
      throwsA(
        isA<ResourceAcquisitionException>()
            .having(
              (error) => error.serviceType,
              'serviceType',
              RuntimeResource,
            )
            .having(
              (error) => error.cause.toString(),
              'dependency trace',
              contains('Database'),
            ),
      ),
    );
  });
}
