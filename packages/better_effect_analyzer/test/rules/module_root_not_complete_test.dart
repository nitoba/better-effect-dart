import 'package:better_effect_analyzer/src/rules/module_root_not_complete.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'rule_test_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ModuleRootNotCompleteTest);
  });
}

@reflectiveTest
final class ModuleRootNotCompleteTest extends BetterEffectRuleTest {
  @override
  void setUp() {
    rule = ModuleRootNotCompleteRule();
    super.setUp();
  }

  Future<void> test_reportsTopLevelStartedRoot() async {
    const source = r'''
import 'package:better_effect/better_effect.dart';

final appModule = Module(const <Binding>[]);

Future<Runtime> start() => appModule.start();
''';

    final offset = source.indexOf('Module(const');
    final length = 'Module(const <Binding>[])'.length;
    await assertDiagnostics(source, [lint(offset, length)]);
  }

  Future<void> test_allowsCompleteRoot() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

final appModule = Module.complete(const <Binding>[]);

Future<Runtime> start() => appModule.start();
''');
  }

  Future<void> test_ignoresComposableLibraryModule() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

final infrastructureModule = Module(const <Binding>[]);
''');
  }

  Future<void> test_reportsFlutterApplicationRoot() async {
    const source = r'''
import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:flutter/widgets.dart';

final appModule = Module(const <Binding>[]);

Future<void> main() {
  return runBetterEffectApp(module: appModule, app: Child());
}

final class Child extends Widget {}
''';

    final offset = source.indexOf('Module(const');
    final length = 'Module(const <Binding>[])'.length;
    await assertDiagnostics(source, [lint(offset, length)]);
  }
}
