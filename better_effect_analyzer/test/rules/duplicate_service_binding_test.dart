import 'package:better_effect_analyzer/src/rules/duplicate_service_binding.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'rule_test_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DuplicateServiceBindingTest);
  });
}

@reflectiveTest
final class DuplicateServiceBindingTest extends BetterEffectRuleTest {
  @override
  void setUp() {
    rule = DuplicateServiceBindingRule();
    super.setUp();
  }

  Future<void> test_reportsSecondDefaultBinding() async {
    const source = r'''
import 'package:better_effect/better_effect.dart';

abstract interface class Database {}
final class PrimaryDatabase implements Database {}
final class TestDatabase implements Database {}

final module = Module([
  .provide<Database>(PrimaryDatabase.new),
  .provide<Database>(TestDatabase.new),
]);
''';

    final offset = source.lastIndexOf('provide');
    await assertDiagnostics(source, [lint(offset, 'provide'.length)]);
  }
}
