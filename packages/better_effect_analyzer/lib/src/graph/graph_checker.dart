import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:path/path.dart' as p;

import '../support/invocation.dart';
import '../support/type_utils.dart';

/// Severity used by project-wide graph diagnostics.
enum GraphDiagnosticSeverity { info, warning, error }

/// A project-wide better_effect graph diagnostic.
final class GraphDiagnostic implements Comparable<GraphDiagnostic> {
  const GraphDiagnostic({
    required this.code,
    required this.message,
    required this.path,
    required this.line,
    required this.column,
    required this.length,
    required this.severity,
  });

  final String code;
  final String message;
  final String path;
  final int line;
  final int column;
  final int length;
  final GraphDiagnosticSeverity severity;

  Map<String, Object> toJson() => <String, Object>{
    'code': code,
    'message': message,
    'path': path,
    'line': line,
    'column': column,
    'length': length,
    'severity': severity.name,
  };

  String toMachine() {
    return '$path:$line:$column:${severity.name}:$code:$message';
  }

  @override
  int compareTo(GraphDiagnostic other) {
    final pathOrder = path.compareTo(other.path);
    if (pathOrder != 0) return pathOrder;

    final lineOrder = line.compareTo(other.line);
    if (lineOrder != 0) return lineOrder;

    final columnOrder = column.compareTo(other.column);
    if (columnOrder != 0) return columnOrder;

    return code.compareTo(other.code);
  }
}

/// Options for [BetterEffectGraphChecker].
final class GraphCheckOptions {
  const GraphCheckOptions({
    this.includeTests = false,
    this.moduleNames = const <String>{},
    this.excludedSuffixes = const <String>{
      '.g.dart',
      '.freezed.dart',
      '.mocks.dart',
      '.gr.dart',
      '.route.dart',
    },
  });

  final bool includeTests;

  /// Optional root Module names. When empty, Modules that are not composed into
  /// another Module are treated as roots.
  final Set<String> moduleNames;

  final Set<String> excludedSuffixes;
}

/// Result returned by [BetterEffectGraphChecker.check].
final class GraphCheckResult {
  GraphCheckResult(Iterable<GraphDiagnostic> diagnostics)
    : diagnostics = List<GraphDiagnostic>.unmodifiable(
        diagnostics.toList()..sort(),
      );

  final List<GraphDiagnostic> diagnostics;

  bool get hasErrors => diagnostics.any(
    (diagnostic) => diagnostic.severity == GraphDiagnosticSeverity.error,
  );

  bool get hasWarnings => diagnostics.any(
    (diagnostic) => diagnostic.severity == GraphDiagnosticSeverity.warning,
  );

  String toJson({bool pretty = true}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();

    return encoder.convert(<String, Object>{
      'diagnostics': diagnostics.map((item) => item.toJson()).toList(),
      'summary': <String, Object>{
        'errors': diagnostics
            .where((item) => item.severity == GraphDiagnosticSeverity.error)
            .length,
        'warnings': diagnostics
            .where((item) => item.severity == GraphDiagnosticSeverity.warning)
            .length,
        'infos': diagnostics
            .where((item) => item.severity == GraphDiagnosticSeverity.info)
            .length,
      },
    });
  }
}

/// Resolves the Dart package and validates complete better_effect Module roots.
///
/// This checker complements the IDE plugin. A normal analysis rule sees one
/// library at a time, while service implementations and their root Modules are
/// often declared in different libraries.
final class BetterEffectGraphChecker {
  BetterEffectGraphChecker(String rootPath)
    : rootPath = p.normalize(p.absolute(rootPath));

  final String rootPath;

  Future<GraphCheckResult> check({
    GraphCheckOptions options = const GraphCheckOptions(),
  }) async {
    final pubspec = File(p.join(rootPath, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw ArgumentError.value(
        rootPath,
        'rootPath',
        'No pubspec.yaml was found at the project root.',
      );
    }

    final includedPaths = <String>[
      if (Directory(p.join(rootPath, 'lib')).existsSync())
        p.join(rootPath, 'lib'),
      if (options.includeTests &&
          Directory(p.join(rootPath, 'test')).existsSync())
        p.join(rootPath, 'test'),
    ];

    if (includedPaths.isEmpty) {
      return GraphCheckResult(const <GraphDiagnostic>[]);
    }

    final collection = AnalysisContextCollection(includedPaths: includedPaths);
    final index = _ProjectIndex(rootPath);

    try {
      for (final context in collection.contexts) {
        final files = context.contextRoot.analyzedFiles().toList()..sort();

        for (final filePath in files) {
          if (!_shouldAnalyze(filePath, options)) continue;

          final result = await context.currentSession.getResolvedUnit(filePath);
          if (result is ResolvedUnitResult) {
            index.addUnit(result);
          }
        }
      }

      return GraphCheckResult(index.validate(moduleNames: options.moduleNames));
    } finally {
      await collection.dispose();
    }
  }

  bool _shouldAnalyze(String filePath, GraphCheckOptions options) {
    if (!filePath.endsWith('.dart')) return false;

    final normalized = p.normalize(filePath);
    if (!p.isWithin(rootPath, normalized)) return false;

    return !options.excludedSuffixes.any(normalized.endsWith);
  }
}

final class _ProjectIndex {
  _ProjectIndex(this.rootPath);

  final String rootPath;
  final Map<String, _ClassInfo> classes = <String, _ClassInfo>{};
  final Map<String, _ModuleInfo> modules = <String, _ModuleInfo>{};
  final Set<String> executionModuleIds = <String>{};

  void addUnit(ResolvedUnitResult result) {
    result.unit.accept(_UnitCollector(result, this));
  }

  Iterable<GraphDiagnostic> validate({required Set<String> moduleNames}) sync* {
    if (moduleNames.isNotEmpty) {
      final availableNames = modules.values
          .map((module) => module.name)
          .toSet();
      for (final requestedName in moduleNames.difference(availableNames)) {
        yield _diagnostic(
          code: 'module_not_found',
          message:
              "No Module named '$requestedName' was found in the analyzed project.",
          location: _SourceLocation(
            path: p.join(rootPath, 'pubspec.yaml'),
            line: 1,
            column: 1,
            length: 1,
          ),
        );
      }
    }

    final referencedModules = <String>{};
    for (final module in modules.values) {
      referencedModules.addAll(module.includedModuleIds);
      final base = module.baseModuleId;
      if (base != null) referencedModules.add(base);
    }

    final roots = modules.values.where((module) {
      if (moduleNames.isNotEmpty) {
        return moduleNames.contains(module.name);
      }
      return !referencedModules.contains(module.id) &&
          !executionModuleIds.contains(module.id);
    });

    for (final root in roots) {
      yield* _validateModule(root);
    }

    // Runtime.runWith/runExitWith/executeWith Modules are overlays. Their
    // unresolved requirements may be supplied by the long-lived root Runtime,
    // while duplicate, incompatible, cyclic and local resource-order defects
    // remain independently valid.
    if (moduleNames.isEmpty) {
      for (final id in executionModuleIds) {
        final module = modules[id];
        if (module != null) {
          yield* _validateModule(module, allowExternalRequirements: true);
        }
      }
    }
  }

  Iterable<GraphDiagnostic> _validateModule(
    _ModuleInfo root, {
    bool allowExternalRequirements = false,
  }) sync* {
    final flattened = <String, _ProviderInfo>{};
    final expansionStack = <String>{};

    Iterable<GraphDiagnostic> expand(_ModuleInfo module) sync* {
      if (!expansionStack.add(module.id)) {
        yield _diagnostic(
          code: 'module_composition_cycle',
          message: "Module composition cycle reaches '${module.name}'.",
          location: module.location,
        );
        return;
      }

      final baseId = module.baseModuleId;
      if (baseId != null) {
        final base = modules[baseId];
        if (base != null) yield* expand(base);
      }

      for (final includedId in module.includedModuleIds) {
        final included = modules[includedId];
        if (included != null) yield* expand(included);
      }

      for (final provider in module.providers) {
        final identity = provider.service.identity;
        final previous = flattened[identity];

        if (previous != null && !module.isOverride) {
          yield _diagnostic(
            code: 'duplicate_service_binding',
            message:
                "Service '${provider.service.display}' is provided more than "
                "once in Module '${root.name}'.",
            location: provider.location,
          );
        }

        // Updating an existing LinkedHashMap key preserves its position. This
        // mirrors Module.overrideWith: replacements stay where the base binding
        // was declared, while new identities are appended.
        flattened[identity] = provider;
      }

      expansionStack.remove(module.id);
    }

    yield* expand(root);

    for (final provider in flattened.values) {
      final implementation = provider.implementation;
      if (implementation != null &&
          !provider.typeSystem.isAssignableTo(
            implementation.type,
            provider.service.type,
            strictCasts: false,
          )) {
        yield _diagnostic(
          code: 'incompatible_provider',
          message:
              "Implementation '${implementation.display}' can't be registered "
              "as '${provider.service.display}'.",
          location: provider.location,
        );
      }

      for (final dependency in _providerDependencies(provider)) {
        if (!flattened.containsKey(dependency.identity) &&
            !allowExternalRequirements) {
          yield _diagnostic(
            code: 'missing_service',
            message:
                "Provider '${provider.service.display}' requires "
                "'${dependency.display}', but Module '${root.name}' doesn't "
                'provide it.',
            location: dependency.location ?? provider.location,
          );
        }
      }
    }

    yield* _validateResourceStartupOrder(root, flattened);
    yield* _findCycles(root, flattened);
  }

  Set<_ServiceRef> _providerDependencies(_ProviderInfo provider) {
    final dependencies = <_ServiceRef>{
      ...provider.constructorDependencies,
      ...provider.inlineDependencies,
    };

    final implementationId = provider.implementation?.baseElementId;
    if (implementationId != null) {
      final implementationClass = classes[implementationId];
      if (implementationClass != null) {
        dependencies.addAll(implementationClass.dependencies);
      }
    }

    return dependencies;
  }

  Iterable<GraphDiagnostic> _validateResourceStartupOrder(
    _ModuleInfo root,
    Map<String, _ProviderInfo> providers,
  ) sync* {
    final ordered = providers.values.toList();
    final positions = <String, int>{
      for (var index = 0; index < ordered.length; index++)
        ordered[index].service.identity: index,
    };
    final emitted = <String>{};

    Iterable<GraphDiagnostic> visit(
      _ProviderInfo owner,
      _ProviderInfo current,
      List<_ServiceRef> path,
      Set<String> visiting,
    ) sync* {
      for (final dependency in _providerDependencies(current)) {
        final target = providers[dependency.identity];
        if (target == null) continue;

        final nextPath = <_ServiceRef>[...path, dependency];
        final ownerPosition = positions[owner.service.identity]!;
        final targetPosition = positions[target.service.identity]!;

        if (target.isResource && targetPosition > ownerPosition) {
          final signature =
              '${owner.service.identity}->${target.service.identity}';
          if (emitted.add(signature)) {
            final displayPath = nextPath
                .map((service) => service.display)
                .join(' -> ');
            yield _diagnostic(
              code: 'resource_dependency_declared_after_provider',
              message:
                  "Resource '${owner.service.display}' requires "
                  "'${target.service.display}' during startup, but that "
                  "resource is acquired later in Module '${root.name}'. "
                  'Dependency path: $displayPath.',
              location: dependency.location ?? owner.location,
            );
          }
          continue;
        }

        // A resource already acquired before the owner has a valid startup
        // state. Constructor-backed providers still need traversal because they
        // can hide a transitive dependency on a later resource.
        if (target.isResource || !visiting.add(target.service.identity)) {
          continue;
        }

        yield* visit(owner, target, nextPath, visiting);
        visiting.remove(target.service.identity);
      }
    }

    for (final provider in ordered) {
      if (!provider.isResource) continue;
      yield* visit(
        provider,
        provider,
        <_ServiceRef>[provider.service],
        <String>{provider.service.identity},
      );
    }
  }

  Iterable<GraphDiagnostic> _findCycles(
    _ModuleInfo root,
    Map<String, _ProviderInfo> providers,
  ) sync* {
    final state = <String, int>{};
    final stack = <String>[];
    final emitted = <String>{};

    Iterable<String> dependenciesOf(_ProviderInfo provider) sync* {
      for (final dependency in _providerDependencies(provider)) {
        if (providers.containsKey(dependency.identity)) {
          yield dependency.identity;
        }
      }
    }

    Iterable<GraphDiagnostic> visit(String identity) sync* {
      state[identity] = 1;
      stack.add(identity);

      final provider = providers[identity]!;
      for (final dependency in dependenciesOf(provider)) {
        if (state[dependency] == 1) {
          final start = stack.indexOf(dependency);
          final cycle = <String>[...stack.sublist(start), dependency];
          final signature = cycle.join(' -> ');

          if (emitted.add(signature)) {
            final names = cycle
                .map((item) => providers[item]?.service.display ?? item)
                .join(' -> ');

            yield _diagnostic(
              code: 'dependency_cycle',
              message: "Dependency cycle in Module '${root.name}': $names.",
              location: provider.location,
            );
          }
          continue;
        }

        if (state[dependency] != 2) {
          yield* visit(dependency);
        }
      }

      stack.removeLast();
      state[identity] = 2;
    }

    for (final identity in providers.keys) {
      if (state[identity] == null) {
        yield* visit(identity);
      }
    }
  }

  GraphDiagnostic _diagnostic({
    required String code,
    required String message,
    required _SourceLocation location,
  }) {
    return GraphDiagnostic(
      code: code,
      message: message,
      path: p.relative(location.path, from: rootPath),
      line: location.line,
      column: location.column,
      length: location.length,
      severity: GraphDiagnosticSeverity.error,
    );
  }
}

final class _UnitCollector extends RecursiveAstVisitor<void> {
  _UnitCollector(this.result, this.index);

  final ResolvedUnitResult result;
  final _ProjectIndex index;
  String? _currentClassId;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final element = node.declaredFragment?.element;
    final classType = element?.thisType;
    final classId = baseTypeElementIdentity(classType);
    final previous = _currentClassId;

    if (classType != null && classId != null) {
      _currentClassId = classId;
      index.classes.putIfAbsent(
        classId,
        () => _ClassInfo(
          type: _ServiceRef.fromType(classType),
          location: _location(
            node.namePart.typeName.offset,
            node.namePart.typeName.length,
          ),
        ),
      );
    }

    super.visitClassDeclaration(node);
    _currentClassId = previous;
  }

  @override
  void visitDotShorthandInvocation(DotShorthandInvocation node) {
    _collectClassDependency(node);
    super.visitDotShorthandInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _collectClassDependency(node);
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _collectClassDependency(node);

    if (node.methodName.name == 'overrideWith' &&
        isModuleType(node.staticType)) {
      _collectOverrideModule(node);
    }

    if (_isExecutionModuleInvocation(node)) {
      _collectExecutionModule(node);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (isModuleType(node.staticType)) {
      _collectModule(node);
    }
    super.visitInstanceCreationExpression(node);
  }

  bool _isExecutionModuleInvocation(MethodInvocation node) {
    return const <String>{
          'runWith',
          'runExitWith',
          'executeWith',
        }.contains(node.methodName.name) &&
        isRuntimeType(node.target?.staticType);
  }

  void _collectExecutionModule(MethodInvocation node) {
    final first = _firstPositionalArgument(node.argumentList);
    if (first is! Expression) return;

    final id = _executionModuleId(first);
    if (id != null) {
      index.executionModuleIds.add(id);
    }
  }

  String? _executionModuleId(Expression expression) {
    if (expression is InstanceCreationExpression &&
        isModuleType(expression.staticType)) {
      return _moduleForDeclaration(
        _moduleDeclarationFor(expression),
        expression,
      ).id;
    }

    if (expression is MethodInvocation &&
        expression.methodName.name == 'overrideWith' &&
        isModuleType(expression.staticType)) {
      return _moduleForDeclaration(
        _moduleDeclarationFor(expression),
        expression,
        isOverride: true,
        baseModuleId: _moduleReferenceId(expression.target),
      ).id;
    }

    return _moduleReferenceId(expression);
  }

  VariableDeclaration? _moduleDeclarationFor(AstNode node) {
    final declaration = node.thisOrAncestorOfType<VariableDeclaration>();
    if (declaration == null) return null;

    return identical(declaration.initializer?.unParenthesized, node)
        ? declaration
        : null;
  }

  void _collectClassDependency(AstNode node) {
    final classId = _currentClassId;
    if (classId == null) return;

    final request = serviceRequestFromNode(node);
    if (request == null) return;

    index.classes[classId]?.dependencies.add(
      _ServiceRef.fromType(
        request.serviceType,
        keyId: request.keyId,
        location: _location(node.offset, node.length),
      ),
    );
  }

  void _collectModule(InstanceCreationExpression node) {
    final declaration = _moduleDeclarationFor(node);
    final module = _moduleForDeclaration(declaration, node);

    if (node.constructorName.name?.name == 'merge') {
      final first = _firstPositionalArgument(node.argumentList);
      if (first is ListLiteral) {
        for (final element in first.elements) {
          if (element is Expression) {
            final id = _moduleReferenceId(element);
            if (id != null) module.includedModuleIds.add(id);
          }
        }
      }
      return;
    }

    final first = _firstPositionalArgument(node.argumentList);
    if (first is ListLiteral) {
      _collectModuleElements(first, module);
    }
  }

  void _collectOverrideModule(MethodInvocation node) {
    final declaration = _moduleDeclarationFor(node);
    final module = _moduleForDeclaration(
      declaration,
      node,
      isOverride: true,
      baseModuleId: _moduleReferenceId(node.target),
    );

    final first = _firstPositionalArgument(node.argumentList);
    if (first is ListLiteral) {
      _collectModuleElements(first, module);
    }
  }

  _ModuleInfo _moduleForDeclaration(
    VariableDeclaration? declaration,
    AstNode node, {
    bool isOverride = false,
    String? baseModuleId,
  }) {
    final name = declaration?.name.lexeme ?? 'module@${node.offset}';
    final element = declaration?.declaredFragment?.element;
    final id = elementIdentity(element) ?? '${result.uri}#$name';

    return index.modules.putIfAbsent(
      id,
      () => _ModuleInfo(
        id: id,
        name: name,
        location: _location(node.offset, node.length),
        isOverride: isOverride,
        baseModuleId: baseModuleId,
      ),
    );
  }

  void _collectModuleElements(ListLiteral list, _ModuleInfo module) {
    for (final element in list.elements) {
      if (element is SpreadElement) {
        final includedId = _moduleReferenceId(element.expression);
        if (includedId != null) module.includedModuleIds.add(includedId);
        continue;
      }

      final binding = bindingCallFromNode(element);
      if (binding != null) {
        final provider = _providerFrom(binding);
        if (provider != null) module.providers.add(provider);
      }
    }
  }

  _ProviderInfo? _providerFrom(BindingCall binding) {
    final serviceType = binding.serviceType;
    if (serviceType == null) return null;

    final implementationType = binding.implementationType(result.typeSystem);
    final constructorDependencies = <_ServiceRef>{};
    final inlineDependencies = <_ServiceRef>{};

    if (binding.isConstructorBacked) {
      final constructorType = binding.firstPositionalArgument?.staticType;
      if (constructorType is FunctionType) {
        for (final parameter in constructorType.formalParameters) {
          if (!parameter.isRequired ||
              result.typeSystem.isNullable(parameter.type)) {
            continue;
          }

          constructorDependencies.add(
            _ServiceRef.fromType(
              parameter.type,
              location: _location(
                binding.implementationNode.offset,
                binding.implementationNode.length,
              ),
            ),
          );
        }
      }
    }

    if (binding.name == 'resource') {
      final acquire = binding.namedArgument('acquire');
      if (acquire != null) {
        final collector = _InlineDependencyCollector((node, request) {
          inlineDependencies.add(
            _ServiceRef.fromType(
              request.serviceType,
              keyId: request.keyId,
              location: _location(node.offset, node.length),
            ),
          );
        });
        acquire.accept(collector);
      }
    }

    return _ProviderInfo(
      service: _ServiceRef.fromType(serviceType, keyId: binding.keyId),
      implementation: implementationType == null
          ? null
          : _ServiceRef.fromType(implementationType),
      constructorDependencies: constructorDependencies,
      inlineDependencies: inlineDependencies,
      isResource: binding.name == 'resource',
      location: _location(binding.nameNode.offset, binding.nameNode.length),
      typeSystem: result.typeSystem,
    );
  }

  String? _moduleReferenceId(Expression? expression) {
    return elementIdentity(referencedElement(expression));
  }

  Expression? _firstPositionalArgument(ArgumentList list) {
    for (final argument in list.arguments) {
      if (argument is! NamedExpression) {
        return argument;
      }
    }
    return null;
  }

  _SourceLocation _location(int offset, int length) {
    final line = result.lineInfo.getLocation(offset);
    return _SourceLocation(
      path: result.path,
      line: line.lineNumber,
      column: line.columnNumber,
      length: length,
    );
  }
}

final class _InlineDependencyCollector extends RecursiveAstVisitor<void> {
  const _InlineDependencyCollector(this.onRequest);

  final void Function(AstNode node, ServiceRequest request) onRequest;

  @override
  void visitDotShorthandInvocation(DotShorthandInvocation node) {
    final request = serviceRequestFromNode(node);
    if (request != null) onRequest(node, request);
    super.visitDotShorthandInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final request = serviceRequestFromNode(node);
    if (request != null) onRequest(node, request);
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final request = serviceRequestFromNode(node);
    if (request != null) onRequest(node, request);
    super.visitMethodInvocation(node);
  }
}

final class _ClassInfo {
  _ClassInfo({required this.type, required this.location});

  final _ServiceRef type;
  final _SourceLocation location;
  final Set<_ServiceRef> dependencies = <_ServiceRef>{};
}

final class _ModuleInfo {
  _ModuleInfo({
    required this.id,
    required this.name,
    required this.location,
    required this.isOverride,
    required this.baseModuleId,
  });

  final String id;
  final String name;
  final _SourceLocation location;
  final bool isOverride;
  final String? baseModuleId;
  final List<_ProviderInfo> providers = <_ProviderInfo>[];
  final Set<String> includedModuleIds = <String>{};
}

final class _ProviderInfo {
  const _ProviderInfo({
    required this.service,
    required this.implementation,
    required this.constructorDependencies,
    required this.inlineDependencies,
    required this.isResource,
    required this.location,
    required this.typeSystem,
  });

  final _ServiceRef service;
  final _ServiceRef? implementation;
  final Set<_ServiceRef> constructorDependencies;
  final Set<_ServiceRef> inlineDependencies;
  final bool isResource;
  final _SourceLocation location;
  final TypeSystem typeSystem;
}

final class _ServiceRef {
  const _ServiceRef({
    required this.baseIdentity,
    required this.baseElementId,
    required this.display,
    required this.type,
    required this.keyId,
    this.location,
  });

  factory _ServiceRef.fromType(
    DartType type, {
    String keyId = '<default>',
    _SourceLocation? location,
  }) {
    return _ServiceRef(
      baseIdentity: typeIdentity(type),
      baseElementId: baseTypeElementIdentity(type),
      display: typeDisplay(type),
      type: type,
      keyId: keyId,
      location: location,
    );
  }

  final String baseIdentity;
  final String? baseElementId;
  final String display;
  final DartType type;
  final String keyId;
  final _SourceLocation? location;

  String get identity => '$baseIdentity::$keyId';

  @override
  bool operator ==(Object other) {
    return other is _ServiceRef && other.identity == identity;
  }

  @override
  int get hashCode => identity.hashCode;
}

final class _SourceLocation {
  const _SourceLocation({
    required this.path,
    required this.line,
    required this.column,
    required this.length,
  });

  final String path;
  final int line;
  final int column;
  final int length;
}
