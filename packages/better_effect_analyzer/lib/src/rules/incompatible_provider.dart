import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../support/invocation.dart';
import '../support/type_utils.dart';

/// Verifies that the implementation registered by a Binding satisfies the
/// service contract in its type argument.
final class IncompatibleProviderRule extends AnalysisRule {
  IncompatibleProviderRule()
      : super(name: code.name, description: code.problemMessage);

  static const code = LintCode(
    'incompatible_provider',
    "The implementation type '{0}' can't be registered as '{1}'.",
    correctionMessage:
        'Register a constructor, instance, or resource compatible with the service type.',
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
    if (call == null) return;

    final serviceType = call.serviceType;
    final implementationType = call.implementationType(context.typeSystem);
    if (serviceType == null || implementationType == null) return;

    final compatible = context.typeSystem.isAssignableTo(
      implementationType,
      serviceType,
      strictCasts: false,
    );

    if (!compatible) {
      rule.reportAtNode(
        call.implementationNode,
        arguments: [
          typeDisplay(implementationType),
          typeDisplay(serviceType),
        ],
      );
    }
  }
}
