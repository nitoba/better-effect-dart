import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../support/type_utils.dart';

/// Reports lazy Effects that are created and immediately discarded.
final class DiscardedEffectRule extends AnalysisRule {
  DiscardedEffectRule()
      : super(name: code.name, description: code.problemMessage);

  static const code = LintCode(
    'discarded_effect',
    'This Effect is lazy and is discarded without being returned, composed, '
        'or executed.',
    correctionMessage:
        'Return it, compose it with use.unwrap, or execute it through a Runtime.',
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
    if (isEffectType(node.expression.staticType)) {
      rule.reportAtNode(node.expression);
    }
  }
}
