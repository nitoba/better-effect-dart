import 'dart:convert';
import 'dart:io';

import 'package:better_effect_analyzer/better_effect_analyzer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late Directory app;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('better_effect_graph_api_');
    app = Directory(p.join(temporary.path, 'app'))..createSync(recursive: true);
    _writePackage(app);
    _writeBetterEffectStub(temporary);
    _writePackageConfig(app, temporary);
    _writeGraphSource(app);
    _writeGeneratedSource(app);
  });

  tearDown(() {
    temporary.deleteSync(recursive: true);
  });

  test('analyze exposes a deterministic immutable graph', () async {
    final checker = BetterEffectGraphChecker(app.path);
    final first = await checker.analyze();
    final second = await checker.analyze();

    expect(first.diagnostics, isEmpty);
    expect(first.graph.rootModuleIds, hasLength(2));
    expect(
      first.graph.rootModuleIds
          .map((id) => first.graph.modulesById[id]!.name)
          .toSet(),
      <String>{'appModule', 'adminModule'},
    );
    expect(
      first.graph.services.map((service) => service.display),
      containsAll(<String>[
        'Database',
        'Repository',
        'AppService',
        'AdminService',
        'RequestContext',
        'RequestRepository',
        'OrphanService',
      ]),
    );
    expect(
      first.graph.modules.any((module) => module.name == 'generatedModule'),
      isFalse,
    );
    expect(
      const JsonEncoder().convert(first.graph.toJson()),
      const JsonEncoder().convert(second.graph.toJson()),
    );
    expect(
      () => first.graph.modules.add(first.graph.modules.first),
      throwsUnsupportedError,
    );
  });

  test('graph JSON has a stable schema and relative locations', () async {
    final graph = await BetterEffectGraphChecker(app.path).graph();
    final json = graph.toJson();

    expect(json['schemaVersion'], betterEffectGraphSchemaVersion);
    expect((json['project'] as Map<String, Object>)['root'], '.');
    final modules = json['modules'] as List<Object>;
    final firstLocation = (modules.first as Map<String, Object?>)['location']
        as Map<String, Object>;
    expect(firstLocation['path'], startsWith('lib/'));
    expect(firstLocation['path'], isNot(contains(app.path)));
  });

  test('explain shows effective providers and root fallback requirements', () async {
    final graph = await BetterEffectGraphChecker(app.path).graph();
    final explanation = graph.explainModule('requestModule');

    expect(explanation.module.isExecutionOverlay, isTrue);
    expect(
      explanation.providers.map((provider) => provider.serviceDisplay),
      containsAll(<String>['RequestContext', 'RequestRepository']),
    );
    expect(
      explanation.externalRequirements.map((service) => service.display),
      contains('Database'),
    );
    expect(explanation.diagnostics, isEmpty);
  });

  test('why returns deterministic shortest paths across selected roots', () async {
    final graph = await BetterEffectGraphChecker(app.path).graph();
    final database = graph.services.singleWhere(
      (service) => service.display == 'Database' && !service.isKeyed,
    );
    final paths = graph.whyService(
      database.id,
      moduleSelectors: const <String>['appModule'],
    );

    expect(paths, hasLength(1));
    expect(
      paths.single.serviceIds
          .map((id) => graph.servicesById[id]!.display)
          .toList(),
      <String>['AppService', 'Repository', 'Database'],
    );
  });

  test('keyed service selectors report useful ambiguity', () async {
    final graph = await BetterEffectGraphChecker(app.path).graph();
    final databases = graph.services
        .where((service) => service.display == 'Database')
        .toList();

    expect(databases, hasLength(3));
    expect(
      () => graph.resolveService('Database'),
      throwsA(
        isA<BetterEffectGraphSelectionException>().having(
          (error) => error.message,
          'message',
          contains('ambiguous'),
        ),
      ),
    );
    final keyed = databases.firstWhere((service) => service.isKeyed);
    expect(graph.resolveService(keyed.selector).id, keyed.id);
  });

  test('unused reports only declarations unreachable from complete roots', () async {
    final graph = await BetterEffectGraphChecker(app.path).graph();
    final unused = graph.unusedDeclarations();

    expect(unused.modules.map((module) => module.name), <String>['orphanModule']);
    expect(
      unused.providers.map((provider) => provider.serviceDisplay),
      <String>['OrphanService'],
    );
    expect(
      unused.providers.map((provider) => provider.serviceDisplay),
      isNot(contains('AppService')),
    );
  });

  test('renders JSON, DOT, Mermaid and SARIF deterministically', () async {
    final analysis = await BetterEffectGraphChecker(app.path).analyze();
    final graph = analysis.graph;

    final json = BetterEffectGraphRenderer.graph(
      graph,
      format: BetterEffectGraphFormat.json,
    );
    final dot = BetterEffectGraphRenderer.graph(
      graph,
      format: BetterEffectGraphFormat.dot,
    );
    final mermaid = BetterEffectGraphRenderer.graph(
      graph,
      format: BetterEffectGraphFormat.mermaid,
    );
    final sarif = BetterEffectGraphRenderer.sarif(<GraphDiagnostic>[
      const GraphDiagnostic(
        code: 'example_rule',
        message: 'Example diagnostic.',
        path: 'lib/app.dart',
        line: 3,
        column: 5,
        length: 7,
        severity: GraphDiagnosticSeverity.warning,
      ),
    ]);

    expect(jsonDecode(json)['schemaVersion'], betterEffectGraphSchemaVersion);
    expect(dot, startsWith('digraph better_effect'));
    expect(dot, contains('constructor'));
    expect(mermaid, startsWith('flowchart LR'));
    expect(mermaid, contains('-->|constructor|'));
    final sarifJson = jsonDecode(sarif) as Map<String, Object?>;
    expect(sarifJson['version'], '2.1.0');
    expect(sarif, contains('example_rule'));
    expect(sarif, contains('endColumn'));
  });

  test('DOT and Mermaid escape labels safely', () {
    final graph = BetterEffectGraph(
      projectName: 'escape',
      rootPath: '/tmp/escape',
      rootModuleIds: const <String>[],
      modules: const <BetterEffectGraphModule>[],
      services: const <BetterEffectGraphService>[
        BetterEffectGraphService(
          id: 'service',
          display: 'Quoted "Service" <value>',
          typeId: 'service',
          keyId: '<default>',
          keyName: null,
        ),
      ],
      providers: const <BetterEffectGraphProvider>[],
      dependencies: const <BetterEffectGraphDependency>[],
      diagnostics: const <BetterEffectGraphDiagnostic>[],
      unreachableModuleIds: const <String>[],
      unreachableProviderIds: const <String>[],
    );

    expect(
      BetterEffectGraphRenderer.graph(
        graph,
        format: BetterEffectGraphFormat.dot,
      ),
      contains(r'Quoted \"Service\" <value>'),
    );
    final mermaid = BetterEffectGraphRenderer.graph(
      graph,
      format: BetterEffectGraphFormat.mermaid,
    );
    expect(mermaid, contains('&quot;Service&quot;'));
    expect(mermaid, contains('&lt;value&gt;'));
  });

  group('CLI inspection', () {
    test('exports graph JSON and SARIF files', () async {
      final graphOutput = File(p.join(temporary.path, 'graph.json'));
      final sarifOutput = File(p.join(temporary.path, 'graph.sarif'));

      final graphResult = await _runCli(<String>[
        '--graph',
        '--format',
        'json',
        '--output',
        graphOutput.path,
        app.path,
      ]);
      final sarifResult = await _runCli(<String>[
        '--format',
        'sarif',
        '--output',
        sarifOutput.path,
        app.path,
      ]);

      expect(graphResult.exitCode, 0, reason: '${graphResult.stderr}');
      expect(sarifResult.exitCode, 0, reason: '${sarifResult.stderr}');
      expect(jsonDecode(graphOutput.readAsStringSync()), isA<Map>());
      expect(
        (jsonDecode(sarifOutput.readAsStringSync()) as Map)['version'],
        '2.1.0',
      );
    });

    test('runs explain, why and unused commands', () async {
      final graph = await BetterEffectGraphChecker(app.path).graph();
      final database = graph.services.singleWhere(
        (service) => service.display == 'Database' && !service.isKeyed,
      );

      final explain = await _runCli(<String>[
        '--explain',
        'appModule',
        app.path,
      ]);
      final why = await _runCli(<String>[
        '--why',
        database.id,
        '--module',
        'appModule',
        app.path,
      ]);
      final unused = await _runCli(<String>['--unused', app.path]);

      expect(explain.exitCode, 0, reason: '${explain.stderr}');
      expect(explain.stdout, contains('providers:'));
      expect(why.exitCode, 0, reason: '${why.stderr}');
      expect(why.stdout, contains('AppService -> Repository -> Database'));
      expect(unused.exitCode, 0, reason: '${unused.stderr}');
      expect(unused.stdout, contains('orphanModule'));
    });
  });
}

Future<ProcessResult> _runCli(List<String> arguments) {
  final executable = p.join(
    Directory.current.path,
    'bin',
    'better_effect_analyzer.dart',
  );
  return Process.run(Platform.resolvedExecutable, <String>[
    executable,
    ...arguments,
  ]);
}

void _writePackage(Directory app) {
  File(p.join(app.path, 'pubspec.yaml')).writeAsStringSync('''
name: graph_public_api_fixture
environment:
  sdk: ^3.10.0
dependencies:
  better_effect: any
''');
  File(p.join(app.path, 'analysis_options.yaml')).writeAsStringSync('''
analyzer:
  language:
    strict-casts: true
''');
}

void _writePackageConfig(Directory app, Directory temporary) {
  final config = Directory(p.join(app.path, '.dart_tool'))
    ..createSync(recursive: true);
  File(p.join(config.path, 'package_config.json')).writeAsStringSync(
    jsonEncode(<String, Object>{
      'configVersion': 2,
      'packages': <Object>[
        <String, Object>{
          'name': 'graph_public_api_fixture',
          'rootUri': '../',
          'packageUri': 'lib/',
          'languageVersion': '3.10',
        },
        <String, Object>{
          'name': 'better_effect',
          'rootUri': p.toUri(
            p.join(temporary.path, 'better_effect'),
          ).toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.10',
        },
      ],
    }),
  );
}

void _writeBetterEffectStub(Directory temporary) {
  final package = Directory(p.join(temporary.path, 'better_effect'))
    ..createSync(recursive: true);
  File(p.join(package.path, 'pubspec.yaml')).writeAsStringSync('''
name: better_effect
environment:
  sdk: ^3.10.0
''');
  final library = File(
    p.join(package.path, 'lib', 'better_effect.dart'),
  )..parent.createSync(recursive: true);
  library.writeAsStringSync('''
library;

final class ServiceKey<T extends Object> {
  const ServiceKey(this.name);
  final String name;
}

enum Lifetime { factory, singleton, lazySingleton }

sealed class Binding {
  const Binding();

  static Binding provide<T extends Object>(
    Function constructor, {
    Lifetime lifetime = Lifetime.lazySingleton,
    ServiceKey<T>? key,
  }) => const _Binding();

  static Binding factory<T extends Object>(
    Function constructor, {
    ServiceKey<T>? key,
  }) => const _Binding();

  static Binding singleton<T extends Object>(
    Function constructor, {
    ServiceKey<T>? key,
  }) => const _Binding();

  static Binding lazySingleton<T extends Object>(
    Function constructor, {
    ServiceKey<T>? key,
  }) => const _Binding();

  static Binding instance<T extends Object>(
    T value, {
    ServiceKey<T>? key,
  }) => const _Binding();

  static Binding resource<T extends Object>({
    required Future<T> Function(Services services) acquire,
    required Future<void> Function(T value, Object exit) release,
    ServiceKey<T>? key,
  }) => const _Binding();
}

final class _Binding extends Binding {
  const _Binding();
}

abstract interface class Services {
  T call<T extends Object>([ServiceKey<T>? key]);
}

final class Effect<A extends Object, E extends Object> {
  const Effect();
}

final class Module implements Iterable<Binding> {
  Module(Iterable<Binding> bindings) : _bindings = List.of(bindings);
  factory Module.complete(Iterable<Binding> bindings) => Module(bindings);

  final List<Binding> _bindings;

  Module overrideWith(Iterable<Binding> bindings) => Module(bindings);

  @override
  Iterator<Binding> get iterator => _bindings.iterator;
}

final class Runtime {
  Future<Object> runWith(Module module, Object effect) async => Object();
  Future<Object> runExitWith(Module module, Object effect) async => Object();
  Object executeWith(Module module, Object effect) => Object();
}
''');
}

void _writeGraphSource(Directory app) {
  final source = File(p.join(app.path, 'lib', 'app.dart'))
    ..parent.createSync(recursive: true);
  source.writeAsStringSync('''
import 'package:better_effect/better_effect.dart';

abstract interface class Database {}
final class DatabaseLive implements Database {}
final class DatabaseReplica implements Database {}

const primaryDatabase = ServiceKey<Database>('primary');
const replicaDatabase = ServiceKey<Database>('replica');

final class Repository {
  const Repository(this.database);
  final Database database;
}

final class AppService {
  const AppService(this.repository);
  final Repository repository;
}

final class AdminService {
  const AdminService(this.database);
  final Database database;
}

final class RequestContext {}
final class RequestRepository {
  const RequestRepository(this.database, this.context);
  final Database database;
  final RequestContext context;
}

final class OrphanService {}

final infrastructureModule = Module([
  .lazySingleton<Database>(DatabaseLive.new),
  .lazySingleton<Database>(DatabaseLive.new, key: primaryDatabase),
  .lazySingleton<Database>(DatabaseReplica.new, key: replicaDatabase),
  .provide<Repository>(Repository.new),
]);

final appModule = Module.complete([
  ...infrastructureModule,
  .factory<AppService>(AppService.new),
]);

final adminModule = Module.complete([
  .lazySingleton<Database>(DatabaseLive.new),
  .provide<AdminService>(AdminService.new),
]);

final orphanModule = Module([
  .singleton<OrphanService>(OrphanService.new),
]);

final requestModule = Module([
  .instance<RequestContext>(RequestContext()),
  .provide<RequestRepository>(RequestRepository.new),
]);

Future<void> handle(Runtime runtime, Object effect) async {
  await runtime.runWith(requestModule, effect);
}
''');
}

void _writeGeneratedSource(Directory app) {
  File(p.join(app.path, 'lib', 'generated.g.dart')).writeAsStringSync('''
import 'package:better_effect/better_effect.dart';
final class GeneratedService {}
final generatedModule = Module.complete([
  .provide<GeneratedService>(GeneratedService.new),
]);
''');
}
