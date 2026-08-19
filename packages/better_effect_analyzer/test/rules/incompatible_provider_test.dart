import 'package:better_effect_analyzer/src/rules/incompatible_provider.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'rule_test_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(IncompatibleProviderTest);
  });
}

@reflectiveTest
final class IncompatibleProviderTest extends BetterEffectRuleTest {
  @override
  void setUp() {
    rule = IncompatibleProviderRule();
    super.setUp();
  }

  Future<void> test_reportsWrongConstructor() async {
    const source = r'''
import 'package:better_effect/better_effect.dart';

abstract interface class UserRepository {}
final class AnalyticsService {}

final module = Module([
  .provide<UserRepository>(AnalyticsService.new),
]);
''';

    final offset = source.indexOf('AnalyticsService.new');
    await assertDiagnostics(source, [
      lint(offset, 'AnalyticsService.new'.length),
    ]);
  }

  Future<void> test_allowsCompatibleConstructor() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

abstract interface class UserRepository {}
final class UserRepositoryLive implements UserRepository {}

final module = Module([
  .provide<UserRepository>(UserRepositoryLive.new),
]);
''');
  }
}
