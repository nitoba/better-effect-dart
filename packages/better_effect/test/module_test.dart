import 'package:better_effect/better_effect.dart';
import 'package:test/test.dart';

abstract interface class Counter {
  int next();
}

final class CounterLive implements Counter {
  int _value = 0;

  @override
  int next() => ++_value;
}

final class FixedCounter implements Counter {
  const FixedCounter(this.value);

  final int value;

  @override
  int next() => value;
}

abstract interface class Database {
  String query();
}

final class DatabaseLive implements Database {
  @override
  String query() => 'database';
}

abstract interface class Repository {
  String load();
}

final class RepositoryLive implements Repository {
  RepositoryLive(this._database);

  final Database _database;

  @override
  String load() => _database.query();
}

final class RuntimeResource {
  const RuntimeResource(this.name);

  final String name;
}

final class EagerService {
  EagerService(this.resource) {
    constructed = true;
  }

  static bool constructed = false;

  final RuntimeResource resource;
}

void main() {
  group('Module and contextual services', () {
    test('resolves a dependency where the Effect uses it', () async {
      final module = Module([.provide<Counter>(CounterLive.new)]);

      final effect = Effect<(int, int), Never>.result((use) async {
        final first = use<Counter>();
        final second = use<Counter>();

        return (first.next(), second.next());
      });

      final result = await module.run(effect);
      final (first, second) = result.getOrThrow();

      expect(first, 1);
      expect(second, 2);
    });

    test('keeps AutoInjector constructor injection available', () async {
      final module = Module([
        .provide<Database>(DatabaseLive.new),
        .provide<Repository>(RepositoryLive.new),
      ]);

      final effect = Effect<String, Never>.result((use) async {
        return use<Repository>().load();
      });

      final result = await module.run(effect);

      expect(result.getOrNull(), 'database');
    });

    test('reports a missing service as a defect', () async {
      final module = Module(const <Binding>[]);
      final effect = Effect<int, Never>.result((use) async {
        return use<Counter>().next();
      });

      final exit = await module.runExit(effect);

      expect(exit, isA<ExitDefect<int, Never>>());
    });
  });

  group('overrides and keys', () {
    test('overrideWith replaces a matching registration', () async {
      final live = Module([.provide<Counter>(CounterLive.new)]);

      final testModule = live.overrideWith([
        .instance<Counter>(const FixedCounter(42)),
      ]);

      final effect = Effect<int, Never>.result((use) async {
        return use<Counter>().next();
      });

      final result = await testModule.run(effect);

      expect(result.getOrNull(), 42);
    });

    test('ServiceKey preserves the resolved type', () async {
      const primary = ServiceKey<Counter>('primary');
      const analytics = ServiceKey<Counter>('analytics');

      final module = Module([
        .instance<Counter>(const FixedCounter(1), key: primary),
        .instance<Counter>(const FixedCounter(2), key: analytics),
      ]);

      final effect = Effect<(int, int), Never>.result((use) async {
        final primaryCounter = use(primary);
        final analyticsCounter = use(analytics);
        return (primaryCounter.next(), analyticsCounter.next());
      });

      final result = await module.run(effect);

      expect(result.getOrNull(), (1, 2));
    });

    test('duplicate bindings are rejected immediately', () {
      expect(
        () => Module([
          .provide<Counter>(CounterLive.new),
          .instance<Counter>(const FixedCounter(1)),
        ]),
        throwsA(isA<DuplicateServiceBindingException>()),
      );
    });
  });

  test('eager singletons initialize after module resources', () async {
    EagerService.constructed = false;

    final module = Module([
      .resource<RuntimeResource>(
        acquire: (_) async => const RuntimeResource('ready'),
        release: (_, _) async {},
      ),
      .singleton<EagerService>(EagerService.new),
    ]);

    final runtime = await module.start();

    try {
      expect(EagerService.constructed, isTrue);
      expect(runtime.services<EagerService>().resource.name, 'ready');
    } finally {
      await runtime.close();
    }
  });
}
