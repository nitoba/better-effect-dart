import 'package:better_effect_analyzer/src/rules/closed_runtime_exposed.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'rule_test_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ClosedRuntimeExposedTest);
  });
}

@reflectiveTest
final class ClosedRuntimeExposedTest extends BetterEffectRuleTest {
  @override
  void setUp() {
    rule = ClosedRuntimeExposedRule();
    super.setUp();
  }

  Future<void> test_reportsUseAfterClose() async {
    const source = r'''
import 'package:better_effect/better_effect.dart';

Future<void> run(Module module, Effect<int, Never> effect) async {
  final runtime = await module.start();
  await runtime.close();
  runtime.execute(effect);
}
''';

    final offset = source.indexOf('runtime.close()');
    await assertDiagnostics(source, [lint(offset, 'runtime.close()'.length)]);
  }

  Future<void> test_allowsStateInspectionAfterClose() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

Future<bool> run(Module module) async {
  final runtime = await module.start();
  await runtime.close();
  return runtime.isClosed;
}
''');
  }

  Future<void> test_allowsNoLaterUse() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

Future<void> run(Module module) async {
  final runtime = await module.start();
  await runtime.close();
}
''');
  }
}
