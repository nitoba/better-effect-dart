import 'dart:async';

import 'package:better_effect_conformance/conformance.dart';
import 'package:flutter_test/flutter_test.dart';

final Set<String> registeredConformanceRuleIds = <String>{};

void conformanceTest(String ruleId, FutureOr<void> Function() body) {
  final rule = conformanceRule(ruleId);
  if (!registeredConformanceRuleIds.add(ruleId)) {
    throw StateError('Conformance rule $ruleId was registered more than once.');
  }

  test('$ruleId — ${rule.summary}', body);
}

void conformanceWidgetTest(
  String ruleId,
  Future<void> Function(WidgetTester tester) body,
) {
  final rule = conformanceRule(ruleId);
  if (!registeredConformanceRuleIds.add(ruleId)) {
    throw StateError('Conformance rule $ruleId was registered more than once.');
  }

  testWidgets('$ruleId — ${rule.summary}', body);
}
