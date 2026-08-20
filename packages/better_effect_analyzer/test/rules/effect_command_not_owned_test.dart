import 'package:better_effect_analyzer/src/rules/effect_command_not_owned.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'rule_test_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(EffectCommandNotOwnedTest);
  });
}

@reflectiveTest
final class EffectCommandNotOwnedTest extends BetterEffectRuleTest {
  @override
  void setUp() {
    rule = EffectCommandNotOwnedRule();
    super.setUp();
  }

  Future<void> test_reportsDirectCommandInViewModel() async {
    const source = r'''
import 'package:better_effect_flutter/better_effect_flutter.dart';

final class AppFailure implements Exception {}

final class UsersViewModel extends EffectViewModel {
  UsersViewModel(super.commands);

  late final load = commands<int, AppFailure>(
    () => Effect<int, AppFailure>.succeed(1),
  );
}
''';

    final offset = source.indexOf('commands<int, AppFailure>');
    final end = source.indexOf(';', offset);
    await assertDiagnostics(source, [lint(offset, end - offset)]);
  }

  Future<void> test_allowsEffectViewModelCommandHelper() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect_flutter/better_effect_flutter.dart';

final class AppFailure implements Exception {}

final class UsersViewModel extends EffectViewModel {
  UsersViewModel(super.commands);

  late final load = command<int, AppFailure>(
    () => Effect<int, AppFailure>.succeed(1),
  );
}
''');
  }

  Future<void> test_allowsExplicitOwnCommand() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect_flutter/better_effect_flutter.dart';

final class AppFailure implements Exception {}

final class UsersViewModel extends EffectViewModel {
  UsersViewModel(super.commands);

  EffectCommand0<int, AppFailure> create() {
    final load = commands<int, AppFailure>(
      () => Effect<int, AppFailure>.succeed(1),
    );
    return ownCommand(load);
  }
}
''');
  }

  Future<void> test_ignoresCommandsOutsideOwningViewModels() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect_flutter/better_effect_flutter.dart';

final class AppFailure implements Exception {}

EffectCommand0<int, AppFailure> create(EffectCommands commands) {
  return commands<int, AppFailure>(
    () => Effect<int, AppFailure>.succeed(1),
  );
}
''');
  }
}
