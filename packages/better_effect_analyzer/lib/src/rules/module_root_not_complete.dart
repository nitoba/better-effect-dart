import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../support/lifecycle_analysis.dart';

/// Opt-in migration rule for application roots that still use `Module(...)`.
final class ModuleRootNotCompleteRule extends AnalysisRule {
  ModuleRootNotCompleteRule()
    : super(name: code.name, description: code.problemMessage);

  static const code = LintCode(
    moduleRootNotCompleteCode,
    moduleRootNotCompleteMessage,
    correctionMessage: moduleRootNotCompleteCorrection,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addVariableDeclaration(this, _Visitor(this));
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  const _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (isUnmarkedApplicationRoot(node)) {
      rule.reportAtNode(node.initializer ?? node);
    }
  }
}
