import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../support/invocation.dart';
import '../support/type_utils.dart';

/// Keeps repository-to-repository orchestration in a UseCase or ViewModel.
final class RepositoryRequestsRepositoryRule extends AnalysisRule {
  RepositoryRequestsRepositoryRule()
    : super(name: code.name, description: code.problemMessage);

  static const code = LintCode(
    'repository_requests_repository',
    "Repository '{0}' requests repository '{1}'.",
    correctionMessage:
        'Move cross-repository orchestration to a UseCase or ViewModel.',
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
    if (request == null || !isRepositoryType(request.serviceType)) return;

    final owner = node.thisOrAncestorOfType<ClassDeclaration>();
    if (owner == null || !isRepositoryClass(owner)) return;

    final ownerType = owner.declaredFragment?.element.thisType;
    if (typeImplements(ownerType, request.serviceType)) return;

    final ownerName = classNameOf(owner);
    final requestedName =
        request.serviceType.element?.name ?? typeDisplay(request.serviceType);

    rule.reportAtNode(request.node, arguments: [ownerName, requestedName]);
  }
}
