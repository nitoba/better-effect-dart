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
        result.diagnostics
            .singleWhere((diagnostic) => diagnostic.code == 'missing_service')
            .message,
        contains("requires 'Database'"),
      );
    });

    test(
      'reports an explicitly requested Module that does not exist',
      () async {
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
      },
    );

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

    test('reports a resource dependency acquired later', () async {
      _writeResourceSource(app, databaseFirst: false);

      final result = await BetterEffectGraphChecker(app.path).check();
      final diagnostic = result.diagnostics.singleWhere(
        (item) => item.code == 'resource_dependency_declared_after_provider',
      );

      expect(diagnostic.message, contains("Resource 'ReportResource'"));
      expect(diagnostic.message, contains("requires 'Database'"));
      expect(diagnostic.message, contains('ReportResource -> Database'));
    });

    test('accepts a resource dependency acquired earlier', () async {
      _writeResourceSource(app, databaseFirst: true);

      final result = await BetterEffectGraphChecker(app.path).check();

      expect(
        result.diagnostics.map((diagnostic) => diagnostic.code),
        isNot(contains('resource_dependency_declared_after_provider')),
      );
    });

    test('reports a transitive later resource dependency', () async {
      _writeTransitiveResourceSource(app);

      final result = await BetterEffectGraphChecker(app.path).check();
      final diagnostic = result.diagnostics.singleWhere(
        (item) => item.code == 'resource_dependency_declared_after_provider',
      );

      expect(
        diagnostic.message,
        contains('ReportResource -> Repository -> Database'),
      );
    });

    test(
      'allows root requirements in a statically visible runWith Module',
      () async {
        _writeExecutionModuleSource(app, invalidLocalResourceOrder: false);

        final result = await BetterEffectGraphChecker(app.path).check();

        expect(
          result.diagnostics.map((diagnostic) => diagnostic.code),
          isNot(contains('missing_service')),
        );
      },
    );

    test('still validates local resource order in a runWith Module', () async {
      _writeExecutionModuleSource(app, invalidLocalResourceOrder: true);

      final result = await BetterEffectGraphChecker(app.path).check();
      final diagnostic = result.diagnostics.singleWhere(
        (item) => item.code == 'resource_dependency_declared_after_provider',
      );

      expect(diagnostic.message, contains("Resource 'RequestResource'"));
      expect(diagnostic.message, contains("requires 'LocalDatabase'"));
    });

    test(
      'uses a statically known parent Runtime to satisfy child requirements',
      () async {
        _writeChildRuntimeSource(app, parentProvidesDatabase: true);

        final result = await BetterEffectGraphChecker(app.path).check();

        expect(
          result.diagnostics.map((diagnostic) => diagnostic.code),
          isNot(contains('missing_service')),
        );
      },
    );

    test(
      'reports child requirements missing from a statically known parent',
      () async {
        _writeChildRuntimeSource(app, parentProvidesDatabase: false);

        final result = await BetterEffectGraphChecker(app.path).check();
        final diagnostic = result.diagnostics.singleWhere(
          (item) => item.code == 'missing_service',
        );

        expect(diagnostic.message, contains("child Module 'featureModule'"));
        expect(diagnostic.message, contains("requires 'Database'"));
        expect(diagnostic.message, contains("'rootModule'"));
      },
    );

    test('follows a statically known nested Runtime parent chain', () async {
      _writeChildRuntimeSource(app, parentProvidesDatabase: true, nested: true);

      final result = await BetterEffectGraphChecker(app.path).check();

      expect(
        result.diagnostics.map((diagnostic) => diagnostic.code),
        isNot(contains('missing_service')),
      );
    });

    test('keeps a Module as a root when it is also used as a child', () async {
      _writeReusedChildRootSource(app);

      final graph = await BetterEffectGraphChecker(app.path).graph();
      final shared = graph.modules.singleWhere(
        (module) => module.name == 'sharedModule',
      );

      expect(shared.isChildRuntimeModule, isTrue);
      expect(shared.rootKind, BetterEffectGraphRootKind.complete);
    });

    test('validates a marked incomplete root at its declaration', () async {
      _writeAppSource(
        app,
        complete: true,
        moduleBindings: '''
  .provide<UserRepository>(UserRepositoryLive.new),
''',
      );

      final result = await BetterEffectGraphChecker(app.path).check();
      final diagnostic = result.diagnostics.singleWhere(
        (item) => item.code == 'missing_service',
      );

      expect(diagnostic.message, contains("Complete Module 'appModule'"));
      expect(diagnostic.message, contains('UserRepository -> Database'));
      expect(diagnostic.path, 'lib/app.dart');
    });

    test('validates several independent complete roots', () async {
      _writeMultipleCompleteRoots(app);

      final result = await BetterEffectGraphChecker(app.path).check();
      final missing = result.diagnostics
          .where((item) => item.code == 'missing_service')
          .toList();

      expect(missing, hasLength(1));
      expect(missing.single.message, contains("'backgroundModule'"));
    });

    test('keeps complete roots across overrideWith', () async {
      _writeCompleteOverrideSource(app, brokenOverride: false);

      final result = await BetterEffectGraphChecker(app.path).check();

      expect(
        result.diagnostics.map((item) => item.code),
        isNot(contains('missing_service')),
      );
    });

    test('reports an override that breaks a complete root', () async {
      _writeCompleteOverrideSource(app, brokenOverride: true);

      final result = await BetterEffectGraphChecker(app.path).check();
      final diagnostic = result.diagnostics.singleWhere(
        (item) => item.code == 'missing_service',
      );

      expect(diagnostic.message, contains('UserRepository -> Cache'));
      expect(diagnostic.message, contains("'appModule'"));
    });

    test('resolves complete roots composed across files', () async {
      _writeCrossFileCompleteRoot(app);

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

  File(
    p.join(dartTool.path, 'package_config.json'),
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(config));
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

  static Binding instance<T extends Object>(
    T value, {
    ServiceKey<T>? key,
  }) => const _Binding();
  static Binding resource<T extends Object>({
    required FutureOr<T> Function(Services services) acquire,
    required FutureOr<void> Function(T value, Object exit) release,
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
  factory Module.complete(Iterable<Binding> bindings) => Module(bindings);
  Module overrideWith(Iterable<Binding> overrides) => this;
  Future<Runtime> start() async => Runtime();
}

final class Runtime {
  Future<Runtime> fork(Module module) async => Runtime();

  Future<void> close() async {}

  Future<Object> runWith(Module module, Object effect) async => Object();

  Future<Object> runExitWith(Module module, Object effect) async => Object();

  Object executeWith(Module module, Object effect) => Object();
}
''');
}

void _writeAppSource(
  Directory app, {
  required String moduleBindings,
  bool complete = false,
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

final appModule = Module${complete ? '.complete' : ''}([
$moduleBindings
]);
''');
}

void _writeResourceSource(Directory app, {required bool databaseFirst}) {
  final source = File(p.join(app.path, 'lib', 'app.dart'))
    ..parent.createSync(recursive: true);
  final database = '''
  .resource<Database>(
    acquire: (_) async => DatabaseLive(),
    release: (_, _) async {},
  ),
''';
  final report = '''
  .resource<ReportResource>(
    acquire: (services) async {
      services<Database>();
      return ReportResource();
    },
    release: (_, _) async {},
  ),
''';

  source.writeAsStringSync('''
import 'package:better_effect/better_effect.dart';

abstract interface class Database {}
final class DatabaseLive implements Database {}
final class ReportResource {}

final appModule = Module([
${databaseFirst ? database : report}
${databaseFirst ? report : database}
]);
''');
}

void _writeTransitiveResourceSource(Directory app) {
  final source = File(p.join(app.path, 'lib', 'app.dart'))
    ..parent.createSync(recursive: true);

  source.writeAsStringSync('''
import 'package:better_effect/better_effect.dart';

abstract interface class Database {}
final class DatabaseLive implements Database {}

final class Repository {
  Repository(this.database);
  final Database database;
}

final class ReportResource {}

final appModule = Module([
  .resource<ReportResource>(
    acquire: (services) async {
      services<Repository>();
      return ReportResource();
    },
    release: (_, _) async {},
  ),
  .provide<Repository>(Repository.new),
  .resource<Database>(
    acquire: (_) async => DatabaseLive(),
    release: (_, _) async {},
  ),
]);
''');
}

void _writeExecutionModuleSource(
  Directory app, {
  required bool invalidLocalResourceOrder,
}) {
  final source = File(p.join(app.path, 'lib', 'execution.dart'))
    ..parent.createSync(recursive: true);

  final orderedBindings = invalidLocalResourceOrder
      ? '''
  .resource<RequestResource>(
    acquire: (services) async {
      services<LocalDatabase>();
      return RequestResource();
    },
    release: (_, _) async {},
  ),
  .resource<LocalDatabase>(
    acquire: (_) async => LocalDatabase(),
    release: (_, _) async {},
  ),
'''
      : '''
  .instance<RequestContext>(RequestContext()),
  .provide<RequestRepository>(RequestRepository.new),
''';

  source.writeAsStringSync('''
import 'package:better_effect/better_effect.dart';

abstract interface class Database {}
final class DatabaseLive implements Database {}
final class RequestContext {}

final class RequestRepository {
  RequestRepository(this.database, this.context);
  final Database database;
  final RequestContext context;
}

final class LocalDatabase {}
final class RequestResource {}
final class AppFailure implements Exception {}

final rootModule = Module([
  .resource<Database>(
    acquire: (_) async => DatabaseLive(),
    release: (_, _) async {},
  ),
]);

final requestModule = Module([
$orderedBindings
]);

Future<void> handle(Runtime runtime) async {
  await runtime.runWith(
    requestModule,
    Effect<int, AppFailure>.result((use) async => 1),
  );
}
''');
}

void _writeChildRuntimeSource(
  Directory app, {
  required bool parentProvidesDatabase,
  bool nested = false,
}) {
  final source = File(p.join(app.path, 'lib', 'child_runtime.dart'))
    ..parent.createSync(recursive: true);
  final rootBinding = parentProvidesDatabase
      ? '.provide<Database>(DatabaseLive.new),'
      : '';
  final setup = nested
      ? '''
  final middle = await root.fork(middleModule);
  final feature = await middle.fork(featureModule);
  try {
    feature.hashCode;
  } finally {
    await feature.close();
    await middle.close();
    await root.close();
  }
'''
      : '''
  final feature = await root.fork(featureModule);
  try {
    feature.hashCode;
  } finally {
    await feature.close();
    await root.close();
  }
''';

  source.writeAsStringSync('''
import 'package:better_effect/better_effect.dart';

abstract interface class Database {}
final class DatabaseLive implements Database {}

final class FeatureRepository {
  FeatureRepository(this.database);
  final Database database;
}

final rootModule = Module([
  $rootBinding
]);

final middleModule = Module(const <Binding>[]);

final featureModule = Module([
  .provide<FeatureRepository>(FeatureRepository.new),
]);

Future<void> buildFeature() async {
  final root = await rootModule.start();
$setup
}
''');
}

void _writeReusedChildRootSource(Directory app) {
  final source = File(p.join(app.path, 'lib', 'reused_child.dart'))
    ..parent.createSync(recursive: true);

  source.writeAsStringSync('''
import 'package:better_effect/better_effect.dart';

final class SharedService {}

final rootModule = Module.complete(const <Binding>[]);
final sharedModule = Module.complete([
  .instance<SharedService>(SharedService()),
]);

Future<void> build() async {
  final root = await rootModule.start();
  final sharedRoot = await sharedModule.start();
  final child = await root.fork(sharedModule);
  try {
    child.hashCode;
  } finally {
    await child.close();
    await sharedRoot.close();
    await root.close();
  }
}
''');
}

void _writeMultipleCompleteRoots(Directory app) {
  final source = File(p.join(app.path, 'lib', 'roots.dart'))
    ..parent.createSync(recursive: true);
  source.writeAsStringSync('''
import 'package:better_effect/better_effect.dart';

abstract interface class Database {}
final class DatabaseLive implements Database {}
final class Api {
  Api(this.database);
  final Database database;
}
final class MissingQueue {}
final class BackgroundJob {
  BackgroundJob(this.queue);
  final MissingQueue queue;
}

final appModule = Module.complete([
  .provide<Database>(DatabaseLive.new),
  .provide<Api>(Api.new),
]);

final backgroundModule = Module.complete([
  .provide<BackgroundJob>(BackgroundJob.new),
]);
''');
}

void _writeCompleteOverrideSource(
  Directory app, {
  required bool brokenOverride,
}) {
  final source = File(p.join(app.path, 'lib', 'override.dart'))
    ..parent.createSync(recursive: true);
  final overrideBinding = brokenOverride
      ? '.provide<UserRepository>(BrokenRepository.new),'
      : '.provide<UserRepository>(UserRepositoryLive.new),';
  source.writeAsStringSync('''
import 'package:better_effect/better_effect.dart';

abstract interface class Database {}
final class DatabaseLive implements Database {}
abstract interface class Cache {}
abstract interface class UserRepository {}
final class UserRepositoryLive implements UserRepository {
  UserRepositoryLive(this.database);
  final Database database;
}
final class BrokenRepository implements UserRepository {
  BrokenRepository(this.cache);
  final Cache cache;
}

final baseModule = Module.complete([
  .provide<Database>(DatabaseLive.new),
  .provide<UserRepository>(UserRepositoryLive.new),
]);

final appModule = baseModule.overrideWith([
  $overrideBinding
]);
''');
}

void _writeCrossFileCompleteRoot(Directory app) {
  final infrastructure = File(p.join(app.path, 'lib', 'infrastructure.dart'))
    ..parent.createSync(recursive: true);
  infrastructure.writeAsStringSync('''
import 'package:better_effect/better_effect.dart';

abstract interface class Database {}
final class DatabaseLive implements Database {}

final infrastructureModule = Module([
  .provide<Database>(DatabaseLive.new),
]);
''');

  final application = File(p.join(app.path, 'lib', 'application.dart'));
  application.writeAsStringSync('''
import 'package:better_effect/better_effect.dart';
import 'infrastructure.dart';

final class Repository {
  Repository(this.database);
  final Database database;
}

final appModule = Module.complete([
  ...infrastructureModule,
  .provide<Repository>(Repository.new),
]);
''');
}
