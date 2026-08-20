import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import 'type_utils.dart';

const runtimeStartedWithoutCloseCode = 'runtime_started_without_close';
const runtimeStartedWithoutCloseMessage =
    'This locally started Runtime has no statically visible lifecycle owner.';
const runtimeStartedWithoutCloseCorrection =
    'Return or store it in a recognized owner, or close it from a try/finally block.';

const discardedEffectExecutionCode = 'discarded_effect_execution';
const discardedEffectExecutionMessage =
    'This managed Effect execution is discarded without observing its Exit or retaining its owner handle.';
const discardedEffectExecutionCorrection =
    'Await its Exit, return it, assign it to an owner, or intentionally pass the Exit to unawaited.';

const effectCommandNotOwnedCode = 'effect_command_not_owned';
const effectCommandNotOwnedMessage =
    'This EffectCommand is created inside an owning ViewModel but is not registered for disposal.';
const effectCommandNotOwnedCorrection =
    'Create it through EffectViewModel.command or wrap it with ownCommand.';

const closedRuntimeExposedCode = 'closed_runtime_exposed';
const closedRuntimeExposedMessage =
    'This Runtime is used after a statically visible close call in the same block.';
const closedRuntimeExposedCorrection =
    'Stop exposing the closed Runtime or move the use before its ownership boundary closes.';

const moduleRootNotCompleteCode = 'module_root_not_complete';
const moduleRootNotCompleteMessage =
    'This application Module is used as a composition root but is not marked with Module.complete.';
const moduleRootNotCompleteCorrection =
    'Use Module.complete so the graph checker can validate this root explicitly.';

enum LifecycleFindingSeverity { info, warning }

final class LifecycleFinding {
  const LifecycleFinding({
    required this.code,
    required this.message,
    required this.correction,
    required this.node,
    required this.severity,
  });

  final String code;
  final String message;
  final String correction;
  final AstNode node;
  final LifecycleFindingSeverity severity;
}

Iterable<LifecycleFinding> collectLifecycleFindings(
  ResolvedUnitResult result, {
  bool includeOptIn = true,
}) sync* {
  final collector = _LifecycleFindingCollector(includeOptIn: includeOptIn);
  result.unit.accept(collector);

  for (final finding in collector.findings) {
    if (!_isSuppressed(result, finding)) {
      yield finding;
    }
  }
}

bool isRuntimeStartInvocation(MethodInvocation node) {
  return node.methodName.name == 'start' &&
      isModuleType(node.target?.staticType);
}

bool isDiscardedEffectExecutionStatement(ExpressionStatement node) {
  return isEffectExecutionType(node.expression.staticType);
}

bool runtimeStartHasKnownOwner(MethodInvocation node) {
  final boundary = _transparentExpressionBoundary(node);
  final parent = boundary.parent;

  if (parent is ReturnStatement) {
    return true;
  }

  if (_isRecognizedRuntimeOwnerArgument(boundary)) {
    return true;
  }

  final declaration = boundary.thisOrAncestorOfType<VariableDeclaration>();
  if (declaration == null || declaration.initializer == null) {
    return false;
  }
  if (!_containsNode(declaration.initializer!, node)) {
    return false;
  }

  final declarationContainer = declaration.parent?.parent;
  if (declarationContainer is FieldDeclaration ||
      declarationContainer is TopLevelVariableDeclaration) {
    // A field or top-level Runtime has escaped the local function. The analyzer
    // cannot prove its owner, so stay conservative rather than reporting.
    return true;
  }

  if (declarationContainer is! VariableDeclarationStatement) {
    return true;
  }

  final block = declarationContainer.parent;
  final element = declaration.declaredFragment?.element;
  if (block is! Block || element == null) {
    return false;
  }

  final statementIndex = block.statements.indexOf(declarationContainer);
  if (statementIndex < 0) {
    return false;
  }

  for (final statement in block.statements.skip(statementIndex + 1)) {
    if (_statementOwnsRuntime(statement, element)) {
      return true;
    }
  }

  return false;
}

bool commandCreationIsOwned(Expression expression) {
  if (!isEffectCommandType(expression.staticType)) {
    return true;
  }

  if (_hasOwningCommandAncestor(expression)) {
    return true;
  }

  final declaration = expression.thisOrAncestorOfType<VariableDeclaration>();
  if (declaration == null || declaration.initializer == null) {
    return false;
  }
  if (!_containsNode(declaration.initializer!, expression)) {
    return false;
  }

  final classNode = declaration.thisOrAncestorOfType<ClassDeclaration>();
  final classType = classNode?.declaredFragment?.element.thisType;
  if (!isEffectCommandOwnerType(classType) &&
      !isEffectViewModelType(classType)) {
    return true;
  }

  final element = declaration.declaredFragment?.element;
  final block = declaration.thisOrAncestorOfType<Block>();
  if (element != null && block != null) {
    final statement = declaration.thisOrAncestorOfType<Statement>();
    final index = statement == null ? -1 : block.statements.indexOf(statement);
    if (index >= 0) {
      for (final later in block.statements.skip(index + 1)) {
        if (_statementOwnsCommand(later, element)) {
          return true;
        }
      }
    }
  }

  return false;
}

bool isClosedRuntimeUse(MethodInvocation closeInvocation) {
  if (closeInvocation.methodName.name != 'close' ||
      !isRuntimeType(closeInvocation.target?.staticType)) {
    return false;
  }

  final target = closeInvocation.target?.unParenthesized;
  if (target is! SimpleIdentifier) {
    return false;
  }
  final element = target.element;
  if (element is! LocalVariableElement) {
    return false;
  }

  final statement = closeInvocation.thisOrAncestorOfType<Statement>();
  final block = statement?.parent;
  if (statement == null || block is! Block) {
    return false;
  }
  final index = block.statements.indexOf(statement);
  if (index < 0) {
    return false;
  }

  for (final later in block.statements.skip(index + 1)) {
    final visitor = _ElementReferenceVisitor(element);
    later.accept(visitor);
    if (visitor.hasDisallowedRuntimeReference) {
      return true;
    }
  }

  return false;
}

bool isUnmarkedApplicationRoot(VariableDeclaration declaration) {
  final initializer = declaration.initializer?.unParenthesized;
  if (initializer == null || !isModuleType(initializer.staticType)) {
    return false;
  }
  if (_isCompleteModuleExpression(initializer)) {
    return false;
  }
  if (declaration.parent?.parent is! TopLevelVariableDeclaration) {
    return false;
  }

  final element = declaration.declaredFragment?.element;
  final unit = declaration.thisOrAncestorOfType<CompilationUnit>();
  if (element == null || unit == null) {
    return false;
  }

  final visitor = _ModuleRootUseVisitor(element);
  unit.accept(visitor);
  return visitor.isRoot;
}

bool _isCompleteModuleExpression(Expression expression) {
  final value = expression.unParenthesized;
  if (value is InstanceCreationExpression &&
      isModuleType(value.staticType) &&
      value.constructorName.name?.name == 'complete') {
    return true;
  }

  if (value is MethodInvocation &&
      value.methodName.name == 'overrideWith' &&
      value.target != null) {
    return _isCompleteModuleExpression(value.target!);
  }

  return false;
}

AstNode _transparentExpressionBoundary(AstNode node) {
  AstNode current = node;
  while (true) {
    final parent = current.parent;
    if (parent is AwaitExpression || parent is ParenthesizedExpression) {
      current = parent!;
      continue;
    }
    return current;
  }
}

bool _isRecognizedRuntimeOwnerArgument(AstNode boundary) {
  AstNode? current = boundary.parent;
  while (current is NamedExpression ||
      current is ArgumentList ||
      current is ParenthesizedExpression ||
      current is AwaitExpression) {
    final parent = current?.parent;
    if (parent is InstanceCreationExpression) {
      final typeName = parent.constructorName.type.toSource().split('.').last;
      final constructorName = parent.constructorName.name?.name;
      return typeName == 'BetterEffectProvider' && constructorName != 'value';
    }
    current = parent;
  }
  return false;
}

bool _statementOwnsRuntime(Statement statement, Element element) {
  if (statement is TryStatement) {
    final finallyBlock = statement.finallyBlock;
    if (finallyBlock != null && _blockClosesRuntime(finallyBlock, element)) {
      return true;
    }
  }

  final visitor = _RuntimeOwnerVisitor(element);
  statement.accept(visitor);
  return visitor.ownsRuntime;
}

bool _blockClosesRuntime(Block block, Element element) {
  final visitor = _RuntimeCloseVisitor(element);
  block.accept(visitor);
  return visitor.closesRuntime;
}

bool _statementOwnsCommand(Statement statement, Element element) {
  final visitor = _CommandOwnerVisitor(element);
  statement.accept(visitor);
  return visitor.ownsCommand;
}

bool _hasOwningCommandAncestor(Expression expression) {
  AstNode? current = expression;
  while (current is ParenthesizedExpression ||
      current is MethodInvocation ||
      current is FunctionExpressionInvocation ||
      current is ArgumentList ||
      current is NamedExpression) {
    if (current is MethodInvocation) {
      final name = current.methodName.name;
      if (name == 'ownCommand' ||
          name == 'command' ||
          name == 'commandWithInput') {
        return true;
      }
    }
    current = current?.parent;
  }
  return false;
}

bool _containsNode(AstNode owner, AstNode target) {
  return owner.offset <= target.offset && target.end <= owner.end;
}

bool _isSuppressed(ResolvedUnitResult result, LifecycleFinding finding) {
  final code = finding.code;
  final prefixed = 'better_effect_analyzer/$code';
  final lines = result.content.split('\n');
  final location = result.lineInfo.getLocation(finding.node.offset);
  final lineIndex = location.lineNumber - 1;

  bool containsCode(String line, String marker) {
    final markerIndex = line.indexOf(marker);
    if (markerIndex < 0) return false;
    final values = line
        .substring(markerIndex + marker.length)
        .split(',')
        .map((value) => value.trim());
    return values.contains(code) || values.contains(prefixed);
  }

  for (final line in lines) {
    if (containsCode(line, 'ignore_for_file:')) {
      return true;
    }
  }

  if (lineIndex >= 0 && lineIndex < lines.length) {
    if (containsCode(lines[lineIndex], 'ignore:')) {
      return true;
    }
  }
  if (lineIndex > 0 && containsCode(lines[lineIndex - 1], 'ignore:')) {
    return true;
  }

  return false;
}

final class _LifecycleFindingCollector extends RecursiveAstVisitor<void> {
  _LifecycleFindingCollector({required this.includeOptIn});

  final bool includeOptIn;
  final List<LifecycleFinding> findings = <LifecycleFinding>[];

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    if (isDiscardedEffectExecutionStatement(node)) {
      findings.add(
        LifecycleFinding(
          code: discardedEffectExecutionCode,
          message: discardedEffectExecutionMessage,
          correction: discardedEffectExecutionCorrection,
          node: node.expression,
          severity: LifecycleFindingSeverity.warning,
        ),
      );
    }

    if (includeOptIn &&
        isEffectCommandType(node.expression.staticType) &&
        !commandCreationIsOwned(node.expression)) {
      findings.add(
        LifecycleFinding(
          code: effectCommandNotOwnedCode,
          message: effectCommandNotOwnedMessage,
          correction: effectCommandNotOwnedCorrection,
          node: node.expression,
          severity: LifecycleFindingSeverity.info,
        ),
      );
    }

    super.visitExpressionStatement(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (isRuntimeStartInvocation(node) && !runtimeStartHasKnownOwner(node)) {
      findings.add(
        LifecycleFinding(
          code: runtimeStartedWithoutCloseCode,
          message: runtimeStartedWithoutCloseMessage,
          correction: runtimeStartedWithoutCloseCorrection,
          node: node,
          severity: LifecycleFindingSeverity.warning,
        ),
      );
    }

    if (includeOptIn && isClosedRuntimeUse(node)) {
      findings.add(
        LifecycleFinding(
          code: closedRuntimeExposedCode,
          message: closedRuntimeExposedMessage,
          correction: closedRuntimeExposedCorrection,
          node: node,
          severity: LifecycleFindingSeverity.info,
        ),
      );
    }

    super.visitMethodInvocation(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final initializer = node.initializer;
    if (includeOptIn &&
        initializer != null &&
        isEffectCommandType(initializer.staticType) &&
        !commandCreationIsOwned(initializer)) {
      findings.add(
        LifecycleFinding(
          code: effectCommandNotOwnedCode,
          message: effectCommandNotOwnedMessage,
          correction: effectCommandNotOwnedCorrection,
          node: initializer,
          severity: LifecycleFindingSeverity.info,
        ),
      );
    }

    if (includeOptIn && isUnmarkedApplicationRoot(node)) {
      findings.add(
        LifecycleFinding(
          code: moduleRootNotCompleteCode,
          message: moduleRootNotCompleteMessage,
          correction: moduleRootNotCompleteCorrection,
          node: initializer ?? node,
          severity: LifecycleFindingSeverity.info,
        ),
      );
    }

    super.visitVariableDeclaration(node);
  }
}

final class _RuntimeCloseVisitor extends RecursiveAstVisitor<void> {
  _RuntimeCloseVisitor(this.element);

  final Element element;
  bool closesRuntime = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target?.unParenthesized;
    if (node.methodName.name == 'close' &&
        target is SimpleIdentifier &&
        refersToSameElement(target.element, element)) {
      closesRuntime = true;
      return;
    }
    super.visitMethodInvocation(node);
  }
}

final class _RuntimeOwnerVisitor extends RecursiveAstVisitor<void> {
  _RuntimeOwnerVisitor(this.element);

  final Element element;
  bool ownsRuntime = false;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = node.constructorName.type.toSource().split('.').last;
    final constructorName = node.constructorName.name?.name;
    if (typeName == 'BetterEffectProvider' && constructorName != 'value') {
      for (final argument in node.argumentList.arguments) {
        if (argument is NamedExpression &&
            argument.name.label.name == 'runtime' &&
            _referencesElement(argument.expression, element)) {
          ownsRuntime = true;
          return;
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'addTearDown' &&
        node.argumentList.arguments.any(
          (argument) => _referencesRuntimeClose(argument, element),
        )) {
      ownsRuntime = true;
      return;
    }
    super.visitMethodInvocation(node);
  }
}

final class _CommandOwnerVisitor extends RecursiveAstVisitor<void> {
  _CommandOwnerVisitor(this.element);

  final Element element;
  bool ownsCommand = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'ownCommand' &&
        node.argumentList.arguments.any(
          (argument) => _referencesElement(argument, element),
        )) {
      ownsCommand = true;
      return;
    }
    super.visitMethodInvocation(node);
  }
}

final class _ElementReferenceVisitor extends RecursiveAstVisitor<void> {
  _ElementReferenceVisitor(this.element);

  final Element element;
  bool hasDisallowedRuntimeReference = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!refersToSameElement(node.element, element) ||
        _isAllowedPostCloseReference(node)) {
      return;
    }
    hasDisallowedRuntimeReference = true;
  }
}

final class _ModuleRootUseVisitor extends RecursiveAstVisitor<void> {
  _ModuleRootUseVisitor(this.element);

  final Element element;
  bool isRoot = false;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = node.constructorName.type.toSource().split('.').last;
    if (typeName == 'BetterEffectBootstrap') {
      for (final argument in node.argumentList.arguments) {
        if (argument is NamedExpression &&
            argument.name.label.name == 'module' &&
            _referencesElement(argument.expression, element)) {
          isRoot = true;
          return;
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target?.unParenthesized;
    if (target is SimpleIdentifier &&
        refersToSameElement(target.element, element)) {
      if (const <String>{
        'start',
        'run',
        'runExit',
      }.contains(node.methodName.name)) {
        isRoot = true;
        return;
      }
    }

    if (node.methodName.name == 'runBetterEffectApp') {
      for (final argument in node.argumentList.arguments) {
        if (argument is NamedExpression &&
            argument.name.label.name == 'module' &&
            _referencesElement(argument.expression, element)) {
          isRoot = true;
          return;
        }
      }
    }
    super.visitMethodInvocation(node);
  }
}

bool _referencesElement(AstNode node, Element element) {
  final visitor = _AnyElementReferenceVisitor(element);
  node.accept(visitor);
  return visitor.found;
}

bool _referencesRuntimeClose(AstNode node, Element element) {
  final value = node is Expression ? node.unParenthesized : node;
  if (value is PrefixedIdentifier &&
      refersToSameElement(value.prefix.element, element) &&
      value.identifier.name == 'close') {
    return true;
  }
  if (value is PropertyAccess &&
      value.target is SimpleIdentifier &&
      refersToSameElement(
        (value.target! as SimpleIdentifier).element,
        element,
      ) &&
      value.propertyName.name == 'close') {
    return true;
  }

  final visitor = _RuntimeCloseVisitor(element);
  node.accept(visitor);
  return visitor.closesRuntime;
}

final class _AnyElementReferenceVisitor extends RecursiveAstVisitor<void> {
  _AnyElementReferenceVisitor(this.element);

  final Element element;
  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (refersToSameElement(node.element, element)) {
      found = true;
      return;
    }
    super.visitSimpleIdentifier(node);
  }
}

bool _isAllowedPostCloseReference(SimpleIdentifier node) {
  final parent = node.parent;
  if (parent is PropertyAccess && parent.target == node) {
    return const <String>{
      'isClosed',
      'state',
    }.contains(parent.propertyName.name);
  }
  if (parent is PrefixedIdentifier && parent.prefix == node) {
    return const <String>{'isClosed', 'state'}.contains(parent.identifier.name);
  }
  if (parent is MethodInvocation &&
      parent.target == node &&
      parent.methodName.name == 'close') {
    return true;
  }
  return false;
}
