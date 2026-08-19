import 'package:better_effect_analyzer/src/rules/missing_binding_type_argument.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'rule_test_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(MissingBindingTypeArgumentTest);
  });
}

@reflectiveTest
final class MissingBindingTypeArgumentTest extends BetterEffectRuleTest {
  @override
  void setUp() {
    rule = MissingBindingTypeArgumentRule();
    super.setUp();
  }

  Future<void> test_reportsConstructorBindingWithoutServiceType() async {
    const source = r'''
import 'package:better_effect/better_effect.dart';

final class DatabaseLive {}

final module = Module([
  .provide(DatabaseLive.new),
]);
''';

    final offset = source.indexOf('provide');
    await assertDiagnostics(source, [lint(offset, 'provide'.length)]);
  }

  Future<void> test_allowsExplicitServiceType() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

abstract interface class Database {}
final class DatabaseLive implements Database {}

final module = Module([
  .provide<Database>(DatabaseLive.new),
]);
''');
  }

  Future<void> test_allowsServiceTypeInferredFromKey() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

abstract interface class Database {}
final class DatabaseLive implements Database {}
const primaryDatabase = ServiceKey<Database>('primary');

final module = Module([
  .provide(DatabaseLive.new, key: primaryDatabase),
]);
''');
  }
}
