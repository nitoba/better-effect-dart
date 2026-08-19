import 'package:better_effect_analyzer/src/rules/unawaited_effect_context_operation.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'rule_test_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(UnawaitedEffectContextOperationTest);
  });
}

@reflectiveTest
final class UnawaitedEffectContextOperationTest
    extends BetterEffectRuleTest {
  @override
  void setUp() {
    rule = UnawaitedEffectContextOperationRule();
    super.setUp();
  }

  Future<void> test_reportsUnawaitedUnwrap() async {
    const source = r'''
import 'package:better_effect/better_effect.dart';

final class AppFailure implements Exception {}

Effect<int, AppFailure> inner() => .succeed(1);

Effect<int, AppFailure> outer() => .result((use) async {
  use.unwrap(inner());
  return 1;
});
''';

    final offset = source.indexOf('unwrap');
    await assertDiagnostics(source, [lint(offset, 'unwrap'.length)]);
  }
}
