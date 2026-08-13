import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../support/invocation.dart';
import '../support/type_utils.dart';

/// Reports constructor-backed Bindings whose service type was inferred as
/// Object because the constructor parameter is intentionally typed Function.
final class MissingBindingTypeArgumentRule extends AnalysisRule {
  MissingBindingTypeArgumentRule()
      : super(name: code.name, description: code.problemMessage);

  static const code = LintCode(
    'missing_binding_type_argument',
    'This constructor-backed Binding does not declare the service type.',
    correctionMessage:
        'Add an explicit type argument, such as .provide<UserRepository>(UserRepositoryLive.new).',
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
      ..addMethodInvocation(this, visitor)
      ..addDotShorthandInvocation(this, visitor);
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  const _Visitor(this.rule);

  final AnalysisRule rule;

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
    if (call == null || !call.isConstructorBacked) return;
    if (call.typeArguments != null) return;
    if (!isUninformativeBindingServiceType(call.serviceType)) return;

    rule.reportAtNode(call.nameNode);
  }
}
