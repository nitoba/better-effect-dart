import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';

const betterEffectLibraryUri = 'package:better_effect/better_effect.dart';
const betterEffectFlutterLibraryUri =
    'package:better_effect_flutter/better_effect_flutter.dart';

/// Normalize a getter/setter reference back to the variable that declared it.
///
/// Top-level variables are read through accessor elements by the analyzer while
/// their declarations expose variable elements. Using the inducing variable
/// keeps Module identities stable between declarations and references.
Element? canonicalElement(Element? element) {
  final value = element?.baseElement;
  if (value is PropertyAccessorElement) {
    return value.variable.baseElement;
  }
  return value;
}

bool refersToSameElement(Element? first, Element? second) {
  final left = canonicalElement(first);
  final right = canonicalElement(second);
  return left != null && identical(left, right);
}

String? elementLibraryUri(Element? element) {
  return canonicalElement(element)?.library?.uri.toString();
}

String? elementIdentity(Element? element) {
  final value = canonicalElement(element);
  final name = value?.name;
  final library = elementLibraryUri(value);
  if (name == null || library == null) return null;

  final enclosingName = value?.enclosingElement?.name;
  if (enclosingName == null || enclosingName.isEmpty) {
    return '$library#$name';
  }

  return '$library#$enclosingName.$name';
}

String typeDisplay(DartType? type) {
  return type?.getDisplayString() ?? 'unknown';
}

String typeIdentity(DartType type) {
  final element = type.element;
  final library = elementLibraryUri(element) ?? '<unknown-library>';
  return '$library#${type.getDisplayString()}';
}

String? baseTypeElementIdentity(DartType? type) {
  return elementIdentity(type?.element);
}

bool isElementFromLibrary(Element? element, String name, String libraryUri) {
  final value = canonicalElement(element);
  return value?.name == name && elementLibraryUri(value) == libraryUri;
}

bool isTypeFromLibrary(DartType? type, String name, String libraryUri) {
  return isElementFromLibrary(type?.element, name, libraryUri);
}

Iterable<InterfaceType> interfaceHierarchy(InterfaceType type) sync* {
  yield type;
  yield* type.element.allSupertypes;
}

bool hierarchyContains(DartType? type, String name, String libraryUri) {
  if (type is! InterfaceType) return false;

  return interfaceHierarchy(type).any(
    (candidate) => isElementFromLibrary(candidate.element, name, libraryUri),
  );
}

bool isEffectType(DartType? type) {
  return isTypeFromLibrary(type, 'Effect', betterEffectLibraryUri);
}

bool isEffectExecutionType(DartType? type) {
  return hierarchyContains(type, 'EffectExecution', betterEffectLibraryUri);
}

bool isEffectContextType(DartType? type) {
  return hierarchyContains(type, 'EffectContext', betterEffectLibraryUri);
}

bool isServicesType(DartType? type) {
  return hierarchyContains(type, 'Services', betterEffectLibraryUri);
}

bool isModuleType(DartType? type) {
  return isTypeFromLibrary(type, 'Module', betterEffectLibraryUri);
}

bool isRuntimeType(DartType? type) {
  return isTypeFromLibrary(type, 'Runtime', betterEffectLibraryUri);
}

bool isBindingMember(Element? element) {
  return element?.enclosingElement?.name == 'Binding' &&
      elementLibraryUri(element) == betterEffectLibraryUri;
}

bool isUninformativeBindingServiceType(DartType? type) {
  if (type == null || type is DynamicType) return true;
  return isTypeFromLibrary(type, 'Object', 'dart:core');
}

bool isStaticEffectService(Element? element) {
  return element?.name == 'service' &&
      element?.enclosingElement?.name == 'Effect' &&
      elementLibraryUri(element) == betterEffectLibraryUri;
}

bool isBuildContextType(DartType? type) {
  if (type is! InterfaceType) return false;

  return interfaceHierarchy(type).any((candidate) {
    final element = candidate.element;
    final uri = element.library.uri.toString();
    return element.name == 'BuildContext' && uri.startsWith('package:flutter/');
  });
}

bool isEffectViewModelType(DartType? type) {
  return hierarchyContains(
    type,
    'EffectViewModel',
    betterEffectFlutterLibraryUri,
  );
}

bool isEffectCommandType(DartType? type) {
  return hierarchyContains(
        type,
        'EffectCommandBase',
        betterEffectFlutterLibraryUri,
      ) ||
      hierarchyContains(
        type,
        'EffectCommandDisposable',
        betterEffectFlutterLibraryUri,
      );
}

bool isEffectCommandOwnerType(DartType? type) {
  return hierarchyContains(
    type,
    'EffectCommandOwner',
    betterEffectFlutterLibraryUri,
  );
}

String classNameOf(ClassDeclaration declaration) {
  return declaration.namePart.typeName.lexeme;
}

bool isRepositoryName(String name) {
  final normalized = name.toLowerCase();
  return normalized.endsWith('repository') ||
      normalized.endsWith('repositorylive');
}

bool isViewModelName(String name) {
  final normalized = name.toLowerCase().replaceAll('_', '');
  return normalized.endsWith('viewmodel');
}

bool isRepositoryType(DartType? type) {
  final name = type?.element?.name;
  return name != null && isRepositoryName(name);
}

bool typeImplements(DartType? type, DartType? contract) {
  if (type is! InterfaceType || contract is! InterfaceType) return false;
  final contractElement = contract.element;
  return interfaceHierarchy(
    type,
  ).any((candidate) => candidate.element == contractElement);
}

bool isViewModelType(DartType? type) {
  final name = type?.element?.name;
  return isEffectViewModelType(type) || (name != null && isViewModelName(name));
}

bool isLowLevelServiceType(DartType? type) {
  final element = type?.element;
  final rawName = element?.name;
  if (rawName == null) return false;

  final name = rawName.toLowerCase().replaceAll('_', '');
  final uri = elementLibraryUri(element)?.toLowerCase() ?? '';

  return name.endsWith('service') ||
      name.endsWith('client') ||
      name.endsWith('api') ||
      name.endsWith('apiclient') ||
      name.endsWith('database') ||
      name.endsWith('datasource') ||
      name.endsWith('storage') ||
      uri.contains('/data/services/') ||
      uri.contains('/data/sources/') ||
      uri.contains('/infrastructure/');
}

bool isBusinessDependencyType(DartType? type) {
  final name = type?.element?.name;
  if (name == null) return false;

  final normalized = name.toLowerCase().replaceAll('_', '');
  return isRepositoryType(type) ||
      isViewModelType(type) ||
      isLowLevelServiceType(type) ||
      normalized.endsWith('usecase') ||
      normalized.endsWith('command') ||
      normalized.endsWith('controller');
}

bool isRepositoryClass(ClassDeclaration declaration) {
  final element = declaration.declaredFragment?.element;
  final name = element?.name ?? classNameOf(declaration);
  return isRepositoryName(name);
}

bool isViewModelClass(ClassDeclaration declaration) {
  final element = declaration.declaredFragment?.element;
  final type = element?.thisType;
  final name = element?.name ?? classNameOf(declaration);
  return isEffectViewModelType(type) || isViewModelName(name);
}

bool isWidgetOrStateClass(ClassDeclaration declaration) {
  final element = declaration.declaredFragment?.element;
  final type = element?.thisType;

  if (type != null) {
    for (final candidate in interfaceHierarchy(type)) {
      final name = candidate.element.name;
      final uri = candidate.element.library.uri.toString();
      if ((name == 'Widget' || name == 'State') &&
          uri.startsWith('package:flutter/')) {
        return true;
      }
    }
  }

  final source = declaration.extendsClause?.superclass.toSource() ?? '';
  return source.endsWith('Widget') || source.startsWith('State<');
}

DartType unwrapFutureOr(DartType type, TypeSystem typeSystem) {
  if (type.isDartAsyncFuture || type.isDartAsyncFutureOr) {
    return typeSystem.futureValueType(type);
  }
  return type;
}

Element? referencedElement(Expression? expression) {
  final unwrapped = expression?.unParenthesized;

  return switch (unwrapped) {
    SimpleIdentifier(:final element) => element,
    PrefixedIdentifier(:final identifier) => identifier.element,
    PropertyAccess(:final propertyName) => propertyName.element,
    _ => null,
  };
}

String keyIdentity(Expression? expression) {
  if (expression == null) return '<default>';

  final element = referencedElement(expression);
  final identity = elementIdentity(element);
  return identity ?? 'source:${expression.toSource()}';
}
