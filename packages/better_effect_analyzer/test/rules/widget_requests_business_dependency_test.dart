import 'package:better_effect_analyzer/src/rules/widget_requests_business_dependency.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'rule_test_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(WidgetRequestsBusinessDependencyTest);
  });
}

@reflectiveTest
final class WidgetRequestsBusinessDependencyTest extends BetterEffectRuleTest {
  @override
  void setUp() {
    rule = WidgetRequestsBusinessDependencyRule();
    super.setUp();
  }

  Future<void> test_reportsRepositoryReadInsideWidget() async {
    const source = r'''
import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:flutter/widgets.dart';

abstract interface class UserRepository {}

final class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final repository = context.readEffectService<UserRepository>();
    return repository as Never;
  }
}
''';

    final offset = source.indexOf('readEffectService');
    await assertDiagnostics(source, [lint(offset, 'readEffectService'.length)]);
  }
}
