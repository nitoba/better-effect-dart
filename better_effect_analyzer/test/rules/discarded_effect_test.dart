import 'package:better_effect_analyzer/src/rules/discarded_effect.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'rule_test_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DiscardedEffectTest);
  });
}

@reflectiveTest
final class DiscardedEffectTest extends BetterEffectRuleTest {
  @override
  void setUp() {
    rule = DiscardedEffectRule();
    super.setUp();
  }

  Future<void> test_reportsDiscardedEffect() async {
    const source = r'''
import 'package:better_effect/better_effect.dart';

final class AppFailure implements Exception {}

Effect<int, AppFailure> operation() => .succeed(1);

void run() {
  operation();
}
''';

    final offset = source.lastIndexOf('operation();');
    await assertDiagnostics(source, [lint(offset, 'operation()'.length)]);
  }

  Future<void> test_allowsReturnedEffect() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

final class AppFailure implements Exception {}

Effect<int, AppFailure> operation() => .succeed(1);
Effect<int, AppFailure> run() => operation();
''');
  }
}
