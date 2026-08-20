import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../support/lifecycle_analysis.dart';
import '../support/type_utils.dart';

/// Opt-in architecture rule for Commands that are not registered for disposal.
final class EffectCommandNotOwnedRule extends AnalysisRule {
  EffectCommandNotOwnedRule()
    : super(name: code.name, description: code.problemMessage);

  static const code = LintCode(
    effectCommandNotOwnedCode,
    effectCommandNotOwnedMessage,
    correctionMessage: effectCommandNotOwnedCorrection,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry
      ..addVariableDeclaration(this, _Visitor(this))
      ..addExpressionStatement(this, _Visitor(this));
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  const _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final initializer = node.initializer;
    if (initializer == null || !isEffectCommandType(initializer.staticType)) {
      return;
    }

    if (!commandCreationIsOwned(initializer)) {
      rule.reportAtNode(initializer);
    }
  }

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    if (isEffectCommandType(node.expression.staticType) &&
        !commandCreationIsOwned(node.expression)) {
      rule.reportAtNode(node.expression);
    }
  }
}
