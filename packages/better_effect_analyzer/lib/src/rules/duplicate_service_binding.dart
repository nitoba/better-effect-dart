import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../support/invocation.dart';
import '../support/type_utils.dart';

/// Reports duplicate service identities in a directly declared Module literal.
final class DuplicateServiceBindingRule extends AnalysisRule {
  DuplicateServiceBindingRule()
      : super(name: code.name, description: code.problemMessage);

  static const code = LintCode(
    'duplicate_service_binding',
    "The service '{0}' is already provided in this Module.",
    correctionMessage:
        'Remove the duplicate binding, use a different ServiceKey, or override it explicitly.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addInstanceCreationExpression(this, _Visitor(this));
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  const _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!isModuleType(node.staticType)) return;
    if (node.constructorName.name?.name == 'merge') return;

    final first = _firstPositionalArgument(node.argumentList);
    if (first is! ListLiteral) return;

    final identities = <String>{};

    for (final element in first.elements) {
      final call = bindingCallFromNode(element);
      final serviceType = call?.serviceType;
      if (call == null || serviceType == null) continue;

      final identity = '${typeIdentity(serviceType)}::${call.keyId}';
      if (!identities.add(identity)) {
        rule.reportAtNode(
          call.nameNode,
          arguments: [typeDisplay(serviceType)],
        );
      }
    }
  }

  Expression? _firstPositionalArgument(ArgumentList list) {
    for (final argument in list.arguments) {
      if (argument is! NamedExpression) {
        return argument;
      }
    }
    return null;
  }
}
