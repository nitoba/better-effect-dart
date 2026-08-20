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
import '../support/lifecycle_analysis.dart';
import '../support/type_utils.dart';
import 'graph_model.dart';

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

/// Public analysis result containing diagnostics and the reusable graph.
final class BetterEffectGraphAnalysis {
  BetterEffectGraphAnalysis({
    required this.graph,
    required Iterable<GraphDiagnostic> diagnostics,
  }) : diagnostics = List<GraphDiagnostic>.unmodifiable(diagnostics);

  final BetterEffectGraph graph;
  final List<GraphDiagnostic> diagnostics;

  GraphCheckResult get checkResult => GraphCheckResult(diagnostics);

  bool get hasErrors => checkResult.hasErrors;

  bool get hasWarnings => checkResult.hasWarnings;
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

  /// Analyze diagnostics and build the immutable public dependency graph.
  Future<BetterEffectGraphAnalysis> analyze({
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
    final index = _ProjectIndex(rootPath);

    if (includedPaths.isEmpty) {
      return BetterEffectGraphAnalysis(
        graph: index.buildGraph(
          moduleNames: options.moduleNames,
          diagnostics: const <GraphDiagnostic>[],
        ),
        diagnostics: const <GraphDiagnostic>[],
      );
    }

    final collection = AnalysisContextCollection(includedPaths: includedPaths);
    final lifecycleDiagnostics = <GraphDiagnostic>[];

    try {
      for (final context in collection.contexts) {
        final files = context.contextRoot.analyzedFiles().toList()..sort();

        for (final filePath in files) {
          if (!_shouldAnalyze(filePath, options)) continue;

          final result = await context.currentSession.getResolvedUnit(filePath);
          if (result is ResolvedUnitResult) {
            index.addUnit(result);
            for (final finding in collectLifecycleFindings(result)) {
              final location = result.lineInfo.getLocation(finding.node.offset);
              lifecycleDiagnostics.add(
                GraphDiagnostic(
                  code: finding.code,
                  message: finding.message,
                  path: p.relative(result.path, from: rootPath),
                  line: location.lineNumber,
                  column: location.columnNumber,
                  length: finding.node.length,
                  severity: finding.severity == LifecycleFindingSeverity.warning
                      ? GraphDiagnosticSeverity.warning
                      : GraphDiagnosticSeverity.info,
                ),
              );
            }
          }
        }
      }

      final checkResult = GraphCheckResult(<GraphDiagnostic>[
        ...index.validate(moduleNames: options.moduleNames),
        ...lifecycleDiagnostics,
      ]);
      return BetterEffectGraphAnalysis(
        graph: index.buildGraph(
          moduleNames: options.moduleNames,
          diagnostics: checkResult.diagnostics,
        ),
        diagnostics: checkResult.diagnostics,
      );
    } finally {
      await collection.dispose();
    }
  }

  /// Compatibility wrapper returning the existing diagnostic-only result.
  Future<GraphCheckResult> check({
    GraphCheckOptions options = const GraphCheckOptions(),
  }) async {
    return (await analyze(options: options)).checkResult;
  }

  /// Build only the reusable public graph.
  Future<BetterEffectGraph> graph({
    GraphCheckOptions options = const GraphCheckOptions(),
  }) async {
    return (await analyze(options: options)).graph;
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

    final explicitRoots = modules.values.where(
      (module) =>
          _isCompleteRoot(module) &&
          !referencedModules.contains(module.id) &&
          !executionModuleIds.contains(module.id),
    );
    final hasExplicitRoots = explicitRoots.isNotEmpty;
    final roots = modules.values.where((module) {
      if (moduleNames.isNotEmpty) {
        return moduleNames.contains(module.name);
      }
      if (hasExplicitRoots) {
        return _isCompleteRoot(module) &&
            !referencedModules.contains(module.id) &&
            !executionModuleIds.contains(module.id);
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

  BetterEffectGraph buildGraph({
    required Set<String> moduleNames,
    required List<GraphDiagnostic> diagnostics,
  }) {
    final rootKinds = _graphRootKinds(moduleNames);
    final moduleValues = modules.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    final graphModules = <BetterEffectGraphModule>[];
    final graphServices = <String, BetterEffectGraphService>{};
    final graphProviders = <BetterEffectGraphProvider>[];
    final graphDependencies = <BetterEffectGraphDependency>[];

    for (final module in moduleValues) {
      final effective =
          <String, ({_ProviderInfo provider, String declaredModuleId})>{};
      _flattenGraphModule(module, effective, <String>{});
      final providerIds = <String>[];
      final declaredProviderIds = <String>[];

      for (final entry in effective.entries) {
        final provider = entry.value.provider;
        final declaredModuleId = entry.value.declaredModuleId;
        final providerId = '${module.id}::${provider.service.identity}';
        providerIds.add(providerId);
        if (declaredModuleId == module.id) {
          declaredProviderIds.add(providerId);
        }
        _registerGraphService(graphServices, provider.service);

        final dependencies =
            <({_ServiceRef service, BetterEffectDependencyKind kind})>[];
        for (final dependency in provider.constructorDependencies) {
          dependencies.add((
            service: dependency,
            kind: BetterEffectDependencyKind.constructor,
          ));
        }
        final implementationId = provider.implementation?.baseElementId;
        final implementationClass = implementationId == null
            ? null
            : classes[implementationId];
        if (implementationClass != null) {
          for (final dependency in implementationClass.dependencies) {
            dependencies.add((
              service: dependency,
              kind: BetterEffectDependencyKind.contextual,
            ));
          }
        }
        for (final dependency in provider.inlineDependencies) {
          dependencies.add((
            service: dependency,
            kind: BetterEffectDependencyKind.resource,
          ));
        }
        dependencies.sort((left, right) {
          final serviceOrder = left.service.identity.compareTo(
            right.service.identity,
          );
          if (serviceOrder != 0) return serviceOrder;
          return left.kind.name.compareTo(right.kind.name);
        });

        final dependencyIds = <String>[];
        final emittedDependencies = <String>{};
        for (final dependency in dependencies) {
          _registerGraphService(graphServices, dependency.service);
          final dependencyId =
              '$providerId::${dependency.kind.name}::${dependency.service.identity}';
          if (!emittedDependencies.add(dependencyId)) continue;
          dependencyIds.add(dependencyId);
          graphDependencies.add(
            BetterEffectGraphDependency(
              id: dependencyId,
              providerId: providerId,
              serviceId: dependency.service.identity,
              kind: dependency.kind,
              isResolved: effective.containsKey(dependency.service.identity),
              location: _publicLocationOrNull(dependency.service.location),
            ),
          );
        }

        graphProviders.add(
          BetterEffectGraphProvider(
            id: providerId,
            moduleId: module.id,
            declaredModuleId: declaredModuleId,
            serviceId: provider.service.identity,
            serviceDisplay: provider.service.display,
            implementationDisplay: provider.implementation?.display,
            lifetime: provider.lifetime,
            isResource: provider.isResource,
            location: _publicLocation(provider.location),
            dependencyIds: dependencyIds,
          ),
        );
      }

      graphModules.add(
        BetterEffectGraphModule(
          id: module.id,
          name: module.name,
          location: _publicLocation(module.location),
          isComplete: _isCompleteRoot(module),
          isExecutionOverlay: executionModuleIds.contains(module.id),
          isOverride: module.isOverride,
          rootKind: rootKinds[module.id],
          baseModuleId: module.baseModuleId,
          includedModuleIds: module.includedModuleIds.toList()..sort(),
          declaredProviderIds: declaredProviderIds,
          providerIds: providerIds,
        ),
      );
    }

    graphProviders.sort((left, right) => left.id.compareTo(right.id));
    graphDependencies.sort((left, right) => left.id.compareTo(right.id));
    final services = graphServices.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    final graphDiagnostics =
        diagnostics
            .map(
              (diagnostic) => BetterEffectGraphDiagnostic(
                code: diagnostic.code,
                message: diagnostic.message,
                severity: BetterEffectGraphDiagnosticSeverity.values.byName(
                  diagnostic.severity.name,
                ),
                location: BetterEffectGraphLocation(
                  path: diagnostic.path,
                  line: diagnostic.line,
                  column: diagnostic.column,
                  length: diagnostic.length,
                ),
              ),
            )
            .toList()
          ..sort((left, right) => left.location.compareTo(right.location));

    final unreachableModules = _unreachableGraphModules(rootKinds);
    final unreachableProviders =
        graphProviders
            .where((provider) => unreachableModules.contains(provider.moduleId))
            .map((provider) => provider.id)
            .toList()
          ..sort();

    return BetterEffectGraph(
      projectName: p.basename(rootPath),
      rootPath: rootPath,
      rootModuleIds: rootKinds.keys.toList()..sort(),
      modules: graphModules,
      services: services,
      providers: graphProviders,
      dependencies: graphDependencies,
      diagnostics: graphDiagnostics,
      unreachableModuleIds: unreachableModules.toList()..sort(),
      unreachableProviderIds: unreachableProviders,
    );
  }

  Map<String, BetterEffectGraphRootKind> _graphRootKinds(
    Set<String> moduleNames,
  ) {
    final referenced = _referencedModuleIds();
    if (moduleNames.isNotEmpty) {
      return <String, BetterEffectGraphRootKind>{
        for (final module in modules.values)
          if (moduleNames.contains(module.name))
            module.id: BetterEffectGraphRootKind.selected,
      };
    }

    final complete = modules.values
        .where(
          (module) =>
              _isCompleteRoot(module) &&
              !referenced.contains(module.id) &&
              !executionModuleIds.contains(module.id),
        )
        .toList();
    if (complete.isNotEmpty) {
      return <String, BetterEffectGraphRootKind>{
        for (final module in complete)
          module.id: BetterEffectGraphRootKind.complete,
      };
    }

    return <String, BetterEffectGraphRootKind>{
      for (final module in modules.values)
        if (!referenced.contains(module.id) &&
            !executionModuleIds.contains(module.id))
          module.id: BetterEffectGraphRootKind.inferred,
    };
  }

  Set<String> _referencedModuleIds() {
    final referenced = <String>{};
    for (final module in modules.values) {
      referenced.addAll(module.includedModuleIds);
      final base = module.baseModuleId;
      if (base != null) {
        referenced.add(base);
      }
    }
    return referenced;
  }

  Set<String> _unreachableGraphModules(
    Map<String, BetterEffectGraphRootKind> rootKinds,
  ) {
    if (!rootKinds.values.contains(BetterEffectGraphRootKind.complete)) {
      return const <String>{};
    }

    final reachable = <String>{};
    void visit(String id) {
      if (!reachable.add(id)) return;
      final module = modules[id];
      if (module == null) return;
      final base = module.baseModuleId;
      if (base != null) visit(base);
      for (final included in module.includedModuleIds) {
        visit(included);
      }
    }

    for (final root in rootKinds.keys) {
      visit(root);
    }
    for (final executionModule in executionModuleIds) {
      visit(executionModule);
    }

    return modules.keys.toSet().difference(reachable);
  }

  void _flattenGraphModule(
    _ModuleInfo module,
    Map<String, ({_ProviderInfo provider, String declaredModuleId})> target,
    Set<String> visiting,
  ) {
    if (!visiting.add(module.id)) return;
    final baseId = module.baseModuleId;
    if (baseId != null) {
      final base = modules[baseId];
      if (base != null) {
        _flattenGraphModule(base, target, visiting);
      }
    }
    for (final includedId in module.includedModuleIds) {
      final included = modules[includedId];
      if (included != null) {
        _flattenGraphModule(included, target, visiting);
      }
    }
    for (final provider in module.providers) {
      target[provider.service.identity] = (
        provider: provider,
        declaredModuleId: module.id,
      );
    }
    visiting.remove(module.id);
  }

  void _registerGraphService(
    Map<String, BetterEffectGraphService> services,
    _ServiceRef service,
  ) {
    services.putIfAbsent(
      service.identity,
      () => BetterEffectGraphService(
        id: service.identity,
        display: service.display,
        typeId: service.baseIdentity,
        keyId: service.keyId,
        keyName: _graphKeyName(service.keyId),
      ),
    );
  }

  String? _graphKeyName(String keyId) {
    if (keyId == '<default>') return null;
    if (keyId.startsWith('source:')) {
      return keyId.substring('source:'.length);
    }
    final hash = keyId.lastIndexOf('#');
    final value = hash < 0 ? keyId : keyId.substring(hash + 1);
    final dot = value.lastIndexOf('.');
    return dot < 0 ? value : value.substring(dot + 1);
  }

  BetterEffectGraphLocation _publicLocation(_SourceLocation location) {
    return BetterEffectGraphLocation(
      path: p.relative(location.path, from: rootPath),
      line: location.line,
      column: location.column,
      length: location.length,
    );
  }

  BetterEffectGraphLocation? _publicLocationOrNull(_SourceLocation? location) {
    return location == null ? null : _publicLocation(location);
  }

  Iterable<GraphDiagnostic> _validateModule(
    _ModuleInfo root, {
    bool allowExternalRequirements = false,
  }) sync* {
    final completeRoot = _isCompleteRoot(root);
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
            !allowExternalRequirements &&
            !completeRoot) {
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

    if (completeRoot && !allowExternalRequirements) {
      yield* _findCompleteRootMissingServices(root, flattened);
    }

    yield* _validateResourceStartupOrder(root, flattened);
    yield* _findCycles(root, flattened);
  }

  bool _isCompleteRoot(_ModuleInfo module, [Set<String>? visiting]) {
    if (module.isComplete) return true;

    final baseId = module.baseModuleId;
    if (baseId == null) return false;

    final seen = visiting ?? <String>{};
    if (!seen.add(module.id)) return false;

    final base = modules[baseId];
    return base != null && _isCompleteRoot(base, seen);
  }

  Iterable<GraphDiagnostic> _findCompleteRootMissingServices(
    _ModuleInfo root,
    Map<String, _ProviderInfo> providers,
  ) sync* {
    final referenced = <String>{};
    for (final provider in providers.values) {
      for (final dependency in _providerDependencies(provider)) {
        if (providers.containsKey(dependency.identity)) {
          referenced.add(dependency.identity);
        }
      }
    }

    final entries = providers.keys
        .where((identity) => !referenced.contains(identity))
        .toList();
    if (entries.isEmpty) entries.addAll(providers.keys);

    final queue = <List<_ServiceRef>>[
      for (final entry in entries) <_ServiceRef>[providers[entry]!.service],
    ];
    final visitedPaths = <String>{};
    final emittedMissing = <String>{};

    while (queue.isNotEmpty) {
      final path = queue.removeAt(0);
      final current = providers[path.last.identity];
      if (current == null) continue;

      final signature = path.map((item) => item.identity).join(' -> ');
      if (!visitedPaths.add(signature)) continue;

      for (final dependency in _providerDependencies(current)) {
        final nextPath = <_ServiceRef>[...path, dependency];
        final target = providers[dependency.identity];
        if (target == null) {
          if (!emittedMissing.add(dependency.identity)) continue;
          final displayPath = nextPath
              .map((service) => service.display)
              .join(' -> ');
          yield _diagnostic(
            code: 'missing_service',
            message:
                "Complete Module '${root.name}' is incomplete. "
                "Dependency path: $displayPath reaches missing service "
                "'${dependency.display}'.",
            location: root.location,
          );
          continue;
        }

        if (!path.any((item) => item.identity == target.service.identity)) {
          queue.add(<_ServiceRef>[...path, target.service]);
        }
      }
    }
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
        baseModuleId: _moduleExpressionId(expression.target),
      ).id;
    }

    return _moduleExpressionId(expression);
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
    final constructorName = node.constructorName.name?.name;
    final module = _moduleForDeclaration(
      declaration,
      node,
      isComplete: constructorName == 'complete',
    );
    if (module.collected) return;
    module.collected = true;

    if (constructorName == 'merge') {
      final first = _firstPositionalArgument(node.argumentList);
      if (first is ListLiteral) {
        for (final element in first.elements) {
          if (element is Expression) {
            final id = _moduleExpressionId(element);
            if (id != null) module.includedModuleIds.add(id);
          }
        }
      }
      return;
    }

    final first = _firstPositionalArgument(node.argumentList);
    if (first is ListLiteral) {
      _collectModuleElements(first, module);
    } else if (first is Expression) {
      final includedId = _moduleExpressionId(first);
      if (includedId != null) module.includedModuleIds.add(includedId);
    }
  }

  void _collectOverrideModule(MethodInvocation node) {
    final declaration = _moduleDeclarationFor(node);
    final module = _moduleForDeclaration(
      declaration,
      node,
      isOverride: true,
      baseModuleId: _moduleExpressionId(node.target),
    );
    if (module.collected) return;
    module.collected = true;

    final first = _firstPositionalArgument(node.argumentList);
    if (first is ListLiteral) {
      _collectModuleElements(first, module);
    }
  }

  _ModuleInfo _moduleForDeclaration(
    VariableDeclaration? declaration,
    AstNode node, {
    bool isOverride = false,
    bool isComplete = false,
    String? baseModuleId,
  }) {
    final name = declaration?.name.lexeme ?? 'module@${node.offset}';
    final element = declaration?.declaredFragment?.element;
    final id = elementIdentity(element) ?? '${result.uri}#$name';

    final module = index.modules.putIfAbsent(
      id,
      () => _ModuleInfo(
        id: id,
        name: name,
        location: _location(node.offset, node.length),
        isOverride: isOverride,
        isComplete: isComplete,
        baseModuleId: baseModuleId,
      ),
    );
    if (isComplete) module.isComplete = true;
    return module;
  }

  void _collectModuleElements(ListLiteral list, _ModuleInfo module) {
    for (final element in list.elements) {
      if (element is SpreadElement) {
        final includedId = _moduleExpressionId(element.expression);
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

  BetterEffectProviderLifetime _bindingLifetime(BindingCall binding) {
    return switch (binding.name) {
      'factory' => BetterEffectProviderLifetime.factory,
      'singleton' => BetterEffectProviderLifetime.singleton,
      'lazySingleton' => BetterEffectProviderLifetime.lazySingleton,
      'instance' => BetterEffectProviderLifetime.instance,
      'resource' => BetterEffectProviderLifetime.resource,
      'provide' => _provideLifetime(binding),
      _ => BetterEffectProviderLifetime.unknown,
    };
  }

  BetterEffectProviderLifetime _provideLifetime(BindingCall binding) {
    final source = binding.namedArgument('lifetime')?.toSource();
    if (source == null || source.endsWith('.lazySingleton')) {
      return BetterEffectProviderLifetime.lazySingleton;
    }
    if (source.endsWith('.factory')) {
      return BetterEffectProviderLifetime.factory;
    }
    if (source.endsWith('.singleton')) {
      return BetterEffectProviderLifetime.singleton;
    }
    return BetterEffectProviderLifetime.unknown;
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
      lifetime: _bindingLifetime(binding),
      isResource: binding.name == 'resource',
      location: _location(binding.nameNode.offset, binding.nameNode.length),
      typeSystem: result.typeSystem,
    );
  }

  String? _moduleExpressionId(Expression? expression) {
    final value = expression?.unParenthesized;
    if (value == null) return null;

    final referenced = referencedElement(value);
    final reference = elementIdentity(referenced);
    if (reference != null) {
      if (index.modules.containsKey(reference)) return reference;

      final referenceName = switch (value) {
        SimpleIdentifier(:final name) => name,
        PrefixedIdentifier(:final identifier) => identifier.name,
        PropertyAccess(:final propertyName) => propertyName.name,
        _ => null,
      };
      final referenceLibrary = elementLibraryUri(referenced);
      if (referenceName != null && referenceLibrary != null) {
        final matches = index.modules.values
            .where(
              (module) =>
                  module.name == referenceName &&
                  module.id.startsWith('$referenceLibrary#'),
            )
            .toList();
        if (matches.length == 1) return matches.single.id;
      }

      return reference;
    }

    if (value is InstanceCreationExpression && isModuleType(value.staticType)) {
      final constructorName = value.constructorName.name?.name;
      return _moduleForDeclaration(
        _moduleDeclarationFor(value),
        value,
        isComplete: constructorName == 'complete',
      ).id;
    }

    if (value is MethodInvocation &&
        value.methodName.name == 'overrideWith' &&
        isModuleType(value.staticType)) {
      return _moduleForDeclaration(
        _moduleDeclarationFor(value),
        value,
        isOverride: true,
        baseModuleId: _moduleExpressionId(value.target),
      ).id;
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
    required this.isComplete,
    required this.baseModuleId,
  });

  final String id;
  final String name;
  final _SourceLocation location;
  final bool isOverride;
  bool isComplete;
  bool collected = false;
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
    required this.lifetime,
    required this.isResource,
    required this.location,
    required this.typeSystem,
  });

  final _ServiceRef service;
  final _ServiceRef? implementation;
  final Set<_ServiceRef> constructorDependencies;
  final Set<_ServiceRef> inlineDependencies;
  final BetterEffectProviderLifetime lifetime;
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
