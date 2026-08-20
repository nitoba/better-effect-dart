import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import '../support/lifecycle_analysis.dart';
import '../support/lifecycle_fix_text.dart';
import '../support/type_utils.dart';

final class ConvertToCompleteModuleFix extends ResolvedCorrectionProducer {
  ConvertToCompleteModuleFix({required super.context});

  static const _kind = FixKind(
    'better_effect.fix.convertToCompleteModule',
    DartFixKindPriority.standard,
    'Mark this Module as a complete composition root',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final creation = node.thisOrAncestorOfType<InstanceCreationExpression>();
    if (creation == null ||
        !isModuleType(creation.staticType) ||
        creation.constructorName.name != null) {
      return;
    }

    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleInsertion(
        creation.constructorName.type.end,
        '.complete',
      );
    });
  }
}

final class AwaitDiscardedExecutionFix extends ResolvedCorrectionProducer {
  AwaitDiscardedExecutionFix({required super.context});

  static const _kind = FixKind(
    'better_effect.fix.awaitDiscardedExecution',
    DartFixKindPriority.standard,
    'Await this managed execution Exit',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final statement = node.thisOrAncestorOfType<ExpressionStatement>();
    final body = getEnclosingFunctionBody();
    if (statement == null || body == null || !body.isAsynchronous) {
      return;
    }

    final expression = statement.expression;
    if (!isEffectExecutionType(expression.staticType)) {
      return;
    }

    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleReplacement(
        SourceRange(expression.offset, expression.length),
        awaitExecutionReplacement(expression.toSource()),
      );
    });
  }
}

final class ReturnDiscardedExecutionFix extends ResolvedCorrectionProducer {
  ReturnDiscardedExecutionFix({required super.context});

  static const _kind = FixKind(
    'better_effect.fix.returnDiscardedExecution',
    DartFixKindPriority.standard - 1,
    'Return this managed execution Exit',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final statement = node.thisOrAncestorOfType<ExpressionStatement>();
    final block = statement?.parent;
    if (statement == null ||
        block is! Block ||
        block.statements.last != statement) {
      return;
    }

    final returnType = _enclosingReturnType(statement);
    if (!_isFutureExitType(returnType)) {
      return;
    }

    final expression = statement.expression;
    if (!isEffectExecutionType(expression.staticType)) {
      return;
    }

    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleReplacement(
        SourceRange(statement.offset, statement.length),
        returnExecutionReplacement(expression.toSource()),
      );
    });
  }
}

final class WrapRuntimeInTryFinallyFix extends ResolvedCorrectionProducer {
  WrapRuntimeInTryFinallyFix({required super.context});

  static const _kind = FixKind(
    'better_effect.fix.wrapRuntimeInTryFinally',
    DartFixKindPriority.standard,
    'Close this Runtime from a try/finally block',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final invocation = node.thisOrAncestorOfType<MethodInvocation>();
    final declaration = invocation?.thisOrAncestorOfType<VariableDeclaration>();
    final declarationStatement = declaration?.parent?.parent;
    final body = getEnclosingFunctionBody();

    if (invocation == null ||
        !isRuntimeStartInvocation(invocation) ||
        declaration == null ||
        declarationStatement is! VariableDeclarationStatement ||
        body == null ||
        !body.isAsynchronous) {
      return;
    }

    final block = declarationStatement.parent;
    if (block is! Block) {
      return;
    }

    final index = block.statements.indexOf(declarationStatement);
    if (index < 0 || index == block.statements.length - 1) {
      return;
    }

    final following = block.statements.skip(index + 1).toList();
    final first = following.first;
    final last = following.last;
    final range = SourceRange(first.offset, last.end - first.offset);
    final statements = utils.getRangeText(range);
    final indentation = utils.getNodePrefix(first);
    final replacement = runtimeTryFinallyReplacement(
      statements: statements,
      indentation: indentation,
      oneIndent: utils.oneIndent,
      runtimeName: declaration.name.lexeme,
    );

    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleReplacement(range, replacement);
      builder.format(SourceRange(first.offset, replacement.length));
    });
  }
}

final class OwnEffectCommandFix extends ResolvedCorrectionProducer {
  OwnEffectCommandFix({required super.context});

  static const _kind = FixKind(
    'better_effect.fix.ownEffectCommand',
    DartFixKindPriority.standard,
    'Register this Command with ownCommand',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final declaration = node.thisOrAncestorOfType<VariableDeclaration>();
    final declarationStatement = declaration?.parent?.parent;
    final initializer = declaration?.initializer;

    // Instance-field initializers cannot safely invoke an instance ownership
    // method. Only offer the transformation for a local declaration.
    if (declaration == null ||
        declarationStatement is! VariableDeclarationStatement ||
        initializer == null ||
        !isEffectCommandType(initializer.staticType) ||
        commandCreationIsOwned(initializer)) {
      return;
    }

    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleReplacement(
        SourceRange(initializer.offset, initializer.length),
        ownCommandReplacement(initializer.toSource()),
      );
    });
  }
}

DartType? _enclosingReturnType(AstNode node) {
  final function = node.thisOrAncestorOfType<FunctionDeclaration>();
  if (function != null) {
    return function.declaredFragment?.element.returnType;
  }

  final method = node.thisOrAncestorOfType<MethodDeclaration>();
  if (method != null) {
    return method.declaredFragment?.element.returnType;
  }

  return null;
}

bool _isFutureExitType(DartType? type) {
  if (type is! InterfaceType ||
      (!type.isDartAsyncFuture && !type.isDartAsyncFutureOr) ||
      type.typeArguments.length != 1) {
    return false;
  }

  return isTypeFromLibrary(
    type.typeArguments.single,
    'Exit',
    betterEffectLibraryUri,
  );
}
