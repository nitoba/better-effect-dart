import 'dart:convert';
import 'dart:io';

import 'package:better_effect_analyzer/better_effect_analyzer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('BetterEffectGraphChecker', () {
    late Directory sandbox;
    late Directory app;

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync(
        'better_effect_analyzer_graph_',
      );
      app = Directory(p.join(sandbox.path, 'app'))..createSync();
      _writeBetterEffectStub(sandbox);
      _writePackage(app);
    });

    tearDown(() {
      sandbox.deleteSync(recursive: true);
    });

    test('reports a contextual service missing from the root Module', () async {
      _writeAppSource(
        app,
        moduleBindings: '''
  .provide<UserRepository>(UserRepositoryLive.new),
''',
      );

      final result = await BetterEffectGraphChecker(app.path).check();

      expect(
        result.diagnostics.map((diagnostic) => diagnostic.code),
        contains('missing_service'),
      );
      expect(
        result.diagnostics.singleWhere(
          (diagnostic) => diagnostic.code == 'missing_service',
        ).message,
        contains("requires 'Database'"),
      );
    });

    test('reports an explicitly requested Module that does not exist', () async {
      _writeAppSource(
        app,
        moduleBindings: '''
  .provide<Database>(DatabaseLive.new),
  .provide<UserRepository>(UserRepositoryLive.new),
''',
      );

      final result = await BetterEffectGraphChecker(app.path).check(
        options: const GraphCheckOptions(
          moduleNames: <String>{'backgroundModule'},
        ),
      );

      expect(
        result.diagnostics.map((diagnostic) => diagnostic.code),
        contains('module_not_found'),
      );
    });

    test('accepts a complete root Module', () async {
      _writeAppSource(
        app,
        moduleBindings: '''
  .provide<Database>(DatabaseLive.new),
  .provide<UserRepository>(UserRepositoryLive.new),
''',
      );

      final result = await BetterEffectGraphChecker(app.path).check();

      expect(result.diagnostics, isEmpty);
    });
  });
}

void _writePackage(Directory app) {
  File(p.join(app.path, 'pubspec.yaml')).writeAsStringSync('''
name: graph_fixture
environment:
  sdk: '>=3.11.0 <4.0.0'
dependencies:
  better_effect:
    path: ../better_effect
''');

  final dartTool = Directory(p.join(app.path, '.dart_tool'))..createSync();
  final config = <String, Object>{
    'configVersion': 2,
    'packages': <Object>[
      <String, Object>{
        'name': 'graph_fixture',
        'rootUri': '../',
        'packageUri': 'lib/',
        'languageVersion': '3.11',
      },
      <String, Object>{
        'name': 'better_effect',
        'rootUri': '../../better_effect/',
        'packageUri': 'lib/',
        'languageVersion': '3.11',
      },
    ],
  };

  File(p.join(dartTool.path, 'package_config.json')).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(config),
  );
}

void _writeBetterEffectStub(Directory sandbox) {
  final library = File(
    p.join(sandbox.path, 'better_effect', 'lib', 'better_effect.dart'),
  )..parent.createSync(recursive: true);

  library.writeAsStringSync(r'''
library;

import 'dart:async';

final class ServiceKey<T extends Object> {
  const ServiceKey(this.name);
  final String name;
}

abstract interface class EffectContext<E extends Object> {
  T call<T extends Object>([ServiceKey<T>? key]);
  T service<T extends Object>([ServiceKey<T>? key]);
}

typedef EffectBody<A extends Object, E extends Object> = FutureOr<A> Function(
  EffectContext<E> use,
);

final class Effect<A extends Object, E extends Object> {
  const Effect._();

  factory Effect.result(EffectBody<A, E> body) => Effect<A, E>._();

  static Effect<T, Never> service<T extends Object>([
    ServiceKey<T>? key,
  ]) => Effect<T, Never>._();
}

enum Lifetime { factory, singleton, lazySingleton }

sealed class Binding {
  const Binding();

  static Binding provide<T extends Object>(
    Function constructor, {
    Lifetime lifetime = Lifetime.lazySingleton,
    ServiceKey<T>? key,
  }) => const _Binding();
}

final class _Binding extends Binding {
  const _Binding();
}

final class Services {
  T call<T extends Object>([ServiceKey<T>? key]) {
    throw UnimplementedError();
  }

  T get<T extends Object>([ServiceKey<T>? key]) {
    throw UnimplementedError();
  }
}

final class Module {
  Module(Iterable<Binding> bindings);
}
''');
}

void _writeAppSource(
  Directory app, {
  required String moduleBindings,
}) {
  final source = File(p.join(app.path, 'lib', 'app.dart'))
    ..parent.createSync(recursive: true);

  source.writeAsStringSync('''
import 'package:better_effect/better_effect.dart';

final class AppFailure implements Exception {}

abstract interface class Database {}
final class DatabaseLive implements Database {}

abstract interface class UserRepository {}
final class UserRepositoryLive implements UserRepository {
  Effect<int, AppFailure> load() => Effect<int, AppFailure>.result((use) async {
    final database = use<Database>();
    return database.hashCode;
  });
}

final appModule = Module([
$moduleBindings
]);
''');
}
