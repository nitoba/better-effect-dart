import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../support/lifecycle_analysis.dart';

/// Opt-in lifecycle rule for a local Runtime used after a visible close call.
final class ClosedRuntimeExposedRule extends AnalysisRule {
  ClosedRuntimeExposedRule()
    : super(name: code.name, description: code.problemMessage);

  static const code = LintCode(
    closedRuntimeExposedCode,
    closedRuntimeExposedMessage,
    correctionMessage: closedRuntimeExposedCorrection,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodInvocation(this, _Visitor(this));
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  const _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (isClosedRuntimeUse(node)) {
      rule.reportAtNode(node);
    }
  }
}
