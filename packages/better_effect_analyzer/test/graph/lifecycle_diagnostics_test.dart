import 'dart:convert';
import 'dart:io';

import 'package:better_effect_analyzer/better_effect_analyzer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('graph CLI lifecycle diagnostics', () {
    late Directory sandbox;
    late Directory app;

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync(
        'better_effect_lifecycle_graph_',
      );
      app = Directory(p.join(sandbox.path, 'app'))..createSync();
      _writeBetterEffectStub(sandbox);
      _writePackage(app);
    });

    tearDown(() {
      sandbox.deleteSync(recursive: true);
    });

    test('uses the IDE lifecycle codes and conservative severities', () async {
      _writeSource(app, r'''
import 'package:better_effect/better_effect.dart';

final appModule = Module(const <Binding>[]);

Future<void> run(Effect<int, Never> effect) async {
  final runtime = await appModule.start();
  runtime.execute(effect);
}
''');

      final result = await BetterEffectGraphChecker(app.path).check();
      final lifecycle = {
        for (final item in result.diagnostics)
          if ({
            'runtime_started_without_close',
            'discarded_effect_execution',
            'module_root_not_complete',
          }.contains(item.code))
            item.code: item,
      };

      expect(lifecycle.keys, {
        'runtime_started_without_close',
        'discarded_effect_execution',
        'module_root_not_complete',
      });
      expect(
        lifecycle['runtime_started_without_close']!.severity,
        GraphDiagnosticSeverity.warning,
      );
      expect(
        lifecycle['discarded_effect_execution']!.severity,
        GraphDiagnosticSeverity.warning,
      );
      expect(
        lifecycle['module_root_not_complete']!.severity,
        GraphDiagnosticSeverity.info,
      );
    });

    test('accepts local and namespaced suppression comments', () async {
      _writeSource(app, r'''
// ignore_for_file: module_root_not_complete
import 'package:better_effect/better_effect.dart';

final appModule = Module(const <Binding>[]);

Future<void> run(Effect<int, Never> effect) async {
  // ignore: better_effect_analyzer/runtime_started_without_close
  final runtime = await appModule.start();
  // ignore: discarded_effect_execution
  runtime.execute(effect);
}
''');

      final result = await BetterEffectGraphChecker(app.path).check();

      expect(
        result.diagnostics.map((item) => item.code),
        isNot(
          containsAll(<String>[
            'runtime_started_without_close',
            'discarded_effect_execution',
            'module_root_not_complete',
          ]),
        ),
      );
      expect(
        result.diagnostics.where(
          (item) => item.code == 'runtime_started_without_close',
        ),
        isEmpty,
      );
      expect(
        result.diagnostics.where(
          (item) => item.code == 'discarded_effect_execution',
        ),
        isEmpty,
      );
      expect(
        result.diagnostics.where(
          (item) => item.code == 'module_root_not_complete',
        ),
        isEmpty,
      );
    });

    test('does not report explicit ownership patterns', () async {
      _writeSource(app, r'''
import 'package:better_effect/better_effect.dart';

final appModule = Module.complete(const <Binding>[]);

Future<void> run(Effect<int, Never> effect) async {
  final runtime = await appModule.start();
  try {
    final execution = runtime.execute(effect);
    await execution.exit;
  } finally {
    await runtime.close();
  }
}
''');

      final result = await BetterEffectGraphChecker(app.path).check();
      final lifecycleCodes = result.diagnostics
          .map((item) => item.code)
          .where(
            (code) =>
                code == 'runtime_started_without_close' ||
                code == 'discarded_effect_execution' ||
                code == 'module_root_not_complete',
          );

      expect(lifecycleCodes, isEmpty);
    });
  });
}

void _writeSource(Directory app, String content) {
  final source = File(p.join(app.path, 'lib', 'app.dart'))
    ..parent.createSync(recursive: true);
  source.writeAsStringSync(content);
}

void _writePackage(Directory app) {
  File(p.join(app.path, 'pubspec.yaml')).writeAsStringSync('''
name: lifecycle_fixture
environment:
  sdk: '>=3.10.0 <4.0.0'
dependencies:
  better_effect:
    path: ../better_effect
''');

  final dartTool = Directory(p.join(app.path, '.dart_tool'))..createSync();
  final config = <String, Object>{
    'configVersion': 2,
    'packages': <Object>[
      <String, Object>{
        'name': 'lifecycle_fixture',
        'rootUri': '../',
        'packageUri': 'lib/',
        'languageVersion': '3.10',
      },
      <String, Object>{
        'name': 'better_effect',
        'rootUri': '../../better_effect/',
        'packageUri': 'lib/',
        'languageVersion': '3.10',
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

sealed class Binding {
  const Binding();
}

sealed class Exit<A extends Object, E extends Object> {}

final class Effect<A extends Object, E extends Object> {
  const Effect();
}

abstract interface class EffectExecution<A extends Object, E extends Object> {
  Future<Exit<A, E>> get exit;
}

final class Runtime {
  EffectExecution<A, E> execute<A extends Object, E extends Object>(
    Effect<A, E> effect,
  ) => throw UnimplementedError();

  Future<void> close() async {}
  bool get isClosed => false;
}

final class Module {
  Module(Iterable<Binding> bindings);
  factory Module.complete(Iterable<Binding> bindings) => Module(bindings);
  Future<Runtime> start() async => Runtime();
}
''');
}
