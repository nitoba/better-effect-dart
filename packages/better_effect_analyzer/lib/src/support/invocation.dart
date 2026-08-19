import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';

import 'type_utils.dart';

const constructorBindingNames = <String>{
  'provide',
  'factory',
  'singleton',
  'lazySingleton',
};

const allBindingNames = <String>{
  ...constructorBindingNames,
  'instance',
  'resource',
};

final class BindingCall {
  const BindingCall({
    required this.node,
    required this.nameNode,
    required this.name,
    required this.element,
    required this.typeArguments,
    required this.typeArgumentTypes,
    required this.argumentList,
  });

  final AstNode node;
  final SimpleIdentifier nameNode;
  final String name;
  final Element? element;
  final TypeArgumentList? typeArguments;
  final List<DartType>? typeArgumentTypes;
  final ArgumentList argumentList;

  DartType? get serviceType {
    final types = typeArgumentTypes;
    return types == null || types.isEmpty ? null : types.first;
  }

  bool get isConstructorBacked => constructorBindingNames.contains(name);

  Expression? get firstPositionalArgument {
    for (final argument in argumentList.arguments) {
      if (argument is! NamedExpression) {
        return argument;
      }
    }
    return null;
  }

  Expression? namedArgument(String name) {
    for (final argument in argumentList.arguments) {
      if (argument is NamedExpression && argument.name.label.name == name) {
        return argument.expression;
      }
    }
    return null;
  }

  String get keyId => keyIdentity(namedArgument('key'));

  bool get usesSingletonLifetime {
    if (name == 'instance' ||
        name == 'resource' ||
        name == 'singleton' ||
        name == 'lazySingleton') {
      return true;
    }
    if (name != 'provide') return false;

    final source = namedArgument('lifetime')?.toSource();
    if (source == null) return true;

    return source == '.singleton' ||
        source == 'Lifetime.singleton' ||
        source.endsWith('.singleton') ||
        source == '.lazySingleton' ||
        source == 'Lifetime.lazySingleton' ||
        source.endsWith('.lazySingleton');
  }

  DartType? implementationType(TypeSystem typeSystem) {
    if (name == 'instance') {
      return firstPositionalArgument?.staticType;
    }

    if (name == 'resource') {
      final acquireType = namedArgument('acquire')?.staticType;
      if (acquireType is FunctionType) {
        return unwrapFutureOr(acquireType.returnType, typeSystem);
      }
      return null;
    }

    final constructorType = firstPositionalArgument?.staticType;
    if (constructorType is FunctionType) {
      return constructorType.returnType;
    }
    return null;
  }

  AstNode get implementationNode {
    if (name == 'resource') {
      return namedArgument('acquire') ?? nameNode;
    }
    return firstPositionalArgument ?? nameNode;
  }
}

BindingCall? bindingCallFromNode(AstNode node) {
  if (node is MethodInvocation) {
    final name = node.methodName.name;
    final element = node.methodName.element;
    if (!allBindingNames.contains(name) || !isBindingMember(element)) {
      return null;
    }

    return BindingCall(
      node: node,
      nameNode: node.methodName,
      name: name,
      element: element,
      typeArguments: node.typeArguments,
      typeArgumentTypes: node.typeArgumentTypes,
      argumentList: node.argumentList,
    );
  }

  if (node is DotShorthandInvocation) {
    final name = node.memberName.name;
    final element = node.memberName.element;
    if (!allBindingNames.contains(name) || !isBindingMember(element)) {
      return null;
    }

    return BindingCall(
      node: node,
      nameNode: node.memberName,
      name: name,
      element: element,
      typeArguments: node.typeArguments,
      typeArgumentTypes: node.typeArgumentTypes,
      argumentList: node.argumentList,
    );
  }

  return null;
}

final class ServiceRequest {
  const ServiceRequest({
    required this.node,
    required this.serviceType,
    required this.keyExpression,
  });

  final AstNode node;
  final DartType serviceType;
  final Expression? keyExpression;

  String get keyId => keyIdentity(keyExpression);
}

ServiceRequest? serviceRequestFromNode(AstNode node) {
  if (node is FunctionExpressionInvocation) {
    final types = node.typeArgumentTypes;
    if (types == null || types.isEmpty) return null;

    final element = node.element;
    final receiverIsContext = isEffectContextType(node.function.staticType) ||
        isServicesType(node.function.staticType);
    final elementIsContextCall = element?.name == 'call' &&
        (element?.enclosingElement?.name == 'EffectContext' ||
            element?.enclosingElement?.name == 'Services') &&
        elementLibraryUri(element) == betterEffectLibraryUri;

    if (!receiverIsContext && !elementIsContextCall) return null;

    return ServiceRequest(
      node: node,
      serviceType: types.first,
      keyExpression: _firstPositionalArgument(node.argumentList),
    );
  }

  if (node is DotShorthandInvocation) {
    final types = node.typeArgumentTypes;
    if (types == null || types.isEmpty) return null;

    final element = node.memberName.element;
    if (!isStaticEffectService(element)) return null;

    return ServiceRequest(
      node: node,
      serviceType: types.first,
      keyExpression: _firstPositionalArgument(node.argumentList),
    );
  }

  if (node is MethodInvocation) {
    final types = node.typeArgumentTypes;
    if (types == null || types.isEmpty) return null;

    final name = node.methodName.name;
    final element = node.methodName.element;
    final targetType = node.target?.staticType;

    final isContextService = name == 'service' &&
        isEffectContextType(targetType);
    final isServicesGet = name == 'get' && isServicesType(targetType);
    final isStaticService = isStaticEffectService(element);

    if (!isContextService && !isServicesGet && !isStaticService) {
      return null;
    }

    return ServiceRequest(
      node: node,
      serviceType: types.first,
      keyExpression: _firstPositionalArgument(node.argumentList),
    );
  }

  return null;
}

Expression? _firstPositionalArgument(ArgumentList list) {
  for (final argument in list.arguments) {
    if (argument is! NamedExpression) {
      return argument;
    }
  }
  return null;
}

final class EffectContextOperation {
  const EffectContextOperation({
    required this.node,
    required this.nameNode,
    required this.name,
  });

  final AstNode node;
  final SimpleIdentifier nameNode;
  final String name;
}

EffectContextOperation? effectContextOperationFromExpression(
  Expression expression,
) {
  if (expression is! MethodInvocation) return null;

  final name = expression.methodName.name;
  if (!const <String>{'unwrap', 'result', 'tryAsync', 'acquire'}
      .contains(name)) {
    return null;
  }

  final element = expression.methodName.element;
  final isContext = isEffectContextType(expression.target?.staticType) ||
      (element?.enclosingElement?.name == 'EffectContext' &&
          elementLibraryUri(element) == betterEffectLibraryUri);

  if (!isContext) return null;

  return EffectContextOperation(
    node: expression,
    nameNode: expression.methodName,
    name: name,
  );
}
