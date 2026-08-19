import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../support/invocation.dart';
import '../support/type_utils.dart';

/// Warns when a ViewModel is registered for the whole application lifetime.
final class SingletonViewModelRule extends AnalysisRule {
  SingletonViewModelRule()
    : super(name: code.name, description: code.problemMessage);

  static const code = LintCode(
    'singleton_viewmodel',
    "ViewModel '{0}' is registered as an application singleton.",
    correctionMessage:
        'Create the ViewModel at the View, route, or feature boundary instead.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addMethodInvocation(this, visitor)
      ..addDotShorthandInvocation(this, visitor);
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  const _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _check(node);
  }

  @override
  void visitDotShorthandInvocation(DotShorthandInvocation node) {
    _check(node);
  }

  void _check(AstNode node) {
    final call = bindingCallFromNode(node);
    if (call == null || !call.usesSingletonLifetime) return;

    final serviceType = call.serviceType;
    final implementationType = call.implementationType(context.typeSystem);
    final viewModelType = isViewModelType(serviceType)
        ? serviceType
        : (isViewModelType(implementationType) ? implementationType : null);

    if (viewModelType == null) return;

    rule.reportAtNode(call.nameNode, arguments: [typeDisplay(viewModelType)]);
  }
}
