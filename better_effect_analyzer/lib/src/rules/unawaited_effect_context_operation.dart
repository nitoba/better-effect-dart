import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../support/invocation.dart';

/// Reports EffectContext operations whose Future and failure propagation are
/// accidentally ignored.
final class UnawaitedEffectContextOperationRule extends AnalysisRule {
  UnawaitedEffectContextOperationRule()
      : super(name: code.name, description: code.problemMessage);

  static const code = LintCode(
    'unawaited_effect_context_operation',
    'The result of this EffectContext operation is ignored.',
    correctionMessage:
        'Await or return the operation so its value and typed failure are propagated.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addExpressionStatement(this, _Visitor(this));
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  const _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    final operation = effectContextOperationFromExpression(node.expression);
    if (operation != null) {
      rule.reportAtNode(operation.nameNode);
    }
  }
}
