import 'package:better_effect_analyzer/src/rules/singleton_viewmodel.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'rule_test_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(SingletonViewModelTest);
  });
}

@reflectiveTest
final class SingletonViewModelTest extends BetterEffectRuleTest {
  @override
  void setUp() {
    rule = SingletonViewModelRule();
    super.setUp();
  }

  Future<void> test_reportsSingletonViewModel() async {
    const source = r'''
import 'package:better_effect/better_effect.dart';
import 'package:better_effect_flutter/better_effect_flutter.dart';

final class HomeViewModel extends EffectViewModel {}

final module = Module([
  .singleton<HomeViewModel>(HomeViewModel.new),
]);
''';

    final offset = source.indexOf('singleton');
    await assertDiagnostics(source, [lint(offset, 'singleton'.length)]);
  }

  Future<void> test_reportsDefaultProvideLifetime() async {
    const source = r'''
import 'package:better_effect/better_effect.dart';
import 'package:better_effect_flutter/better_effect_flutter.dart';

final class HomeViewModel extends EffectViewModel {}

final module = Module([
  .provide<HomeViewModel>(HomeViewModel.new),
]);
''';

    final offset = source.indexOf('provide');
    await assertDiagnostics(source, [lint(offset, 'provide'.length)]);
  }

  Future<void> test_reportsProvideWithSingletonLifetime() async {
    const source = r'''
import 'package:better_effect/better_effect.dart';
import 'package:better_effect_flutter/better_effect_flutter.dart';

final class HomeViewModel extends EffectViewModel {}

final module = Module([
  .provide<HomeViewModel>(
    HomeViewModel.new,
    lifetime: .singleton,
  ),
]);
''';

    final offset = source.indexOf('provide');
    await assertDiagnostics(source, [lint(offset, 'provide'.length)]);
  }

  Future<void> test_reportsViewModelInstance() async {
    const source = r'''
import 'package:better_effect/better_effect.dart';
import 'package:better_effect_flutter/better_effect_flutter.dart';

final class HomeViewModel extends EffectViewModel {}

final module = Module([
  .instance<HomeViewModel>(HomeViewModel()),
]);
''';

    final offset = source.indexOf('instance');
    await assertDiagnostics(source, [lint(offset, 'instance'.length)]);
  }

  Future<void> test_allowsFactoryViewModel() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';
import 'package:better_effect_flutter/better_effect_flutter.dart';

final class HomeViewModel extends EffectViewModel {}

final module = Module([
  .factory<HomeViewModel>(HomeViewModel.new),
]);
''');
  }
}
