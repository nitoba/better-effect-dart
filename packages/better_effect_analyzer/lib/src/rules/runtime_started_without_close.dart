import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../support/lifecycle_analysis.dart';
import '../support/type_utils.dart';

/// Reports locally created Runtimes with no statically visible owner.
final class RuntimeStartedWithoutCloseRule extends AnalysisRule {
  RuntimeStartedWithoutCloseRule()
    : super(name: code.name, description: code.problemMessage);

  static const code = LintCode(
    runtimeStartedWithoutCloseCode,
    runtimeStartedWithoutCloseMessage,
    correctionMessage: runtimeStartedWithoutCloseCorrection,
    severity: DiagnosticSeverity.WARNING,
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
    final isRuntimeFork =
        node.methodName.name == 'fork' &&
        isRuntimeType(node.target?.staticType);
    final createsRuntime = isRuntimeStartInvocation(node) || isRuntimeFork;

    if (createsRuntime && !runtimeStartHasKnownOwner(node)) {
      rule.reportAtNode(node);
    }
  }
}
