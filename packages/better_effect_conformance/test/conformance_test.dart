import 'dart:io';

import 'package:better_effect_conformance/conformance.dart';
import 'package:flutter_test/flutter_test.dart';

import 'src/core_concurrency_retry_scenarios.dart';
import 'src/core_effect_outcome_scenarios.dart';
import 'src/core_scope_runtime_scenarios.dart';
import 'src/flutter_command_scenarios.dart';
import 'src/flutter_ownership_scenarios.dart';
import 'src/registry.dart';

void main() {
  registerCoreEffectOutcomeScenarios();
  registerCoreScopeRuntimeScenarios();
  registerCoreConcurrencyRetryScenarios();
  registerFlutterCommandScenarios();
  registerFlutterOwnershipScenarios();

  test('the normative catalog is documented and fully executable', () {
    expect(
      normativeConformanceRulesById.length,
      normativeConformanceRules.length,
      reason: 'Normative rule IDs must be unique.',
    );

    final expected = normativeConformanceRulesById.keys.toSet();
    expect(
      registeredConformanceRuleIds,
      expected,
      reason: 'Every normative rule must register exactly one scenario.',
    );

    final semantics = File('../../SEMANTICS.md').readAsStringSync();
    for (final rule in normativeConformanceRules) {
      expect(
        semantics,
        contains('`${rule.id}`'),
        reason: '${rule.id} must remain documented in SEMANTICS.md.',
      );
    }
  });
}
