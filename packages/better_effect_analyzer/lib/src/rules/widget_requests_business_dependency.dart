import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../support/type_utils.dart';

/// Prevents Widgets from resolving repositories, use cases, and infrastructure
/// directly through BuildContext.
final class WidgetRequestsBusinessDependencyRule extends AnalysisRule {
  WidgetRequestsBusinessDependencyRule()
    : super(name: code.name, description: code.problemMessage);

  static const code = LintCode(
    'widget_requests_business_dependency',
    "Widget '{0}' resolves business dependency '{1}' directly.",
    correctionMessage:
        'Expose the dependency through the ViewModel and let the View observe '
        'its state or commands.',
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
    if (node.methodName.name != 'readEffectService') return;
    if (!isBuildContextType(node.target?.staticType)) return;

    final element = node.methodName.element;
    if (elementLibraryUri(element) != betterEffectFlutterLibraryUri) return;

    final types = node.typeArgumentTypes;
    if (types == null || types.isEmpty) return;

    final requested = types.first;
    if (!isBusinessDependencyType(requested)) return;

    final owner = node.thisOrAncestorOfType<ClassDeclaration>();
    if (owner == null || !isWidgetOrStateClass(owner)) return;

    rule.reportAtNode(
      node.methodName,
      arguments: [
        classNameOf(owner),
        requested.element?.name ?? typeDisplay(requested),
      ],
    );
  }
}
