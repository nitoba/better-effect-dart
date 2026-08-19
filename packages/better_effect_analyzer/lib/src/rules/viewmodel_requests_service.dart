import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../support/invocation.dart';
import '../support/type_utils.dart';

/// Encourages ViewModels to depend on repositories or use cases rather than
/// low-level infrastructure services.
final class ViewModelRequestsServiceRule extends AnalysisRule {
  ViewModelRequestsServiceRule()
      : super(name: code.name, description: code.problemMessage);

  static const code = LintCode(
    'viewmodel_requests_service',
    "ViewModel '{0}' requests low-level service '{1}'.",
    correctionMessage:
        'Expose this operation through a Repository or UseCase and request '
        'that abstraction instead.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry
      ..addDotShorthandInvocation(this, visitor)
      ..addFunctionExpressionInvocation(this, visitor)
      ..addMethodInvocation(this, visitor);
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  const _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitDotShorthandInvocation(DotShorthandInvocation node) {
    _check(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _check(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _check(node);
  }

  void _check(AstNode node) {
    final request = serviceRequestFromNode(node);
    if (request == null || !isLowLevelServiceType(request.serviceType)) {
      return;
    }

    final owner = node.thisOrAncestorOfType<ClassDeclaration>();
    if (owner == null || !isViewModelClass(owner)) return;

    rule.reportAtNode(
      request.node,
      arguments: [
        classNameOf(owner),
        request.serviceType.element?.name ?? typeDisplay(request.serviceType),
      ],
    );
  }
}
