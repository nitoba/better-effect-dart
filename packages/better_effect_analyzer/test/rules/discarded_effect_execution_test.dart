import 'package:better_effect_analyzer/src/rules/discarded_effect_execution.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'rule_test_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DiscardedEffectExecutionTest);
  });
}

@reflectiveTest
final class DiscardedEffectExecutionTest extends BetterEffectRuleTest {
  @override
  void setUp() {
    rule = DiscardedEffectExecutionRule();
    super.setUp();
  }

  Future<void> test_reportsDiscardedExecution() async {
    const source = r'''
import 'package:better_effect/better_effect.dart';

void run(Runtime runtime, Effect<int, Never> effect) {
  runtime.execute(effect);
}
''';

    final offset = source.indexOf('runtime.execute(effect)');
    await assertDiagnostics(source, [
      lint(offset, 'runtime.execute(effect)'.length),
    ]);
  }

  Future<void> test_allowsAssignedExecution() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

EffectExecution<int, Never> run(
  Runtime runtime,
  Effect<int, Never> effect,
) {
  final execution = runtime.execute(effect);
  return execution;
}
''');
  }

  Future<void> test_allowsObservedExit() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

Future<Exit<int, Never>> run(
  Runtime runtime,
  Effect<int, Never> effect,
) async {
  return runtime.execute(effect).exit;
}
''');
  }
}
