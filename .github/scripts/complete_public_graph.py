from pathlib import Path


path = Path('packages/better_effect_analyzer/lib/src/graph/graph_checker.dart')
source = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one match, found {count}')
    source = source.replace(old, new, 1)


if "import 'graph_model.dart';" not in source:
    replace_once(
        "import '../support/type_utils.dart';\n",
        "import '../support/type_utils.dart';\nimport 'graph_model.dart';\n",
        'graph model import',
    )

if 'final class BetterEffectGraphAnalysis' not in source:
    marker = '/// Resolves the Dart package and validates complete better_effect Module roots.\n'
    analysis_result = '''/// Public analysis result containing diagnostics and the reusable graph.
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

'''
    replace_once(marker, analysis_result + marker, 'analysis result')

start = source.index('  Future<GraphCheckResult> check({')
end = source.index('\n  bool _shouldAnalyze', start)
new_methods = '''  /// Analyze diagnostics and build the immutable public dependency graph.
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
'''
source = source[:start] + new_methods + source[end:]

if 'BetterEffectGraph buildGraph({' not in source:
    marker = '  Iterable<GraphDiagnostic> _validateModule(\n'
    build_graph = r'''  BetterEffectGraph buildGraph({
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
      final effective = LinkedHashMap<
        String,
        ({_ProviderInfo provider, String declaredModuleId})
      >();
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

        final dependencies = <
          ({_ServiceRef service, BetterEffectDependencyKind kind})
        >[];
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
    final graphDiagnostics = diagnostics
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
    final unreachableProviders = graphProviders
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
    return <String>{
      for (final module in modules.values) ...module.includedModuleIds,
      for (final module in modules.values)
        if (module.baseModuleId case final base?) base,
    };
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

    return modules.keys.difference(reachable);
  }

  void _flattenGraphModule(
    _ModuleInfo module,
    LinkedHashMap<
      String,
      ({_ProviderInfo provider, String declaredModuleId})
    > target,
    Set<String> visiting,
  ) {
    if (!visiting.add(module.id)) return;
    final baseId = module.baseModuleId;
    if (baseId != null && modules[baseId] case final base?) {
      _flattenGraphModule(base, target, visiting);
    }
    for (final includedId in module.includedModuleIds) {
      if (modules[includedId] case final included?) {
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

  BetterEffectGraphLocation? _publicLocationOrNull(
    _SourceLocation? location,
  ) {
    return location == null ? null : _publicLocation(location);
  }

'''
    replace_once(marker, build_graph + marker, 'public graph builder')

provider_return = '''    return _ProviderInfo(
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
'''
if 'lifetime: _bindingLifetime(binding),' not in source:
    replace_once(
        provider_return,
        provider_return.replace(
            '      inlineDependencies: inlineDependencies,\n',
            '      inlineDependencies: inlineDependencies,\n'
            '      lifetime: _bindingLifetime(binding),\n',
        ),
        'provider lifetime argument',
    )

if 'BetterEffectProviderLifetime _bindingLifetime' not in source:
    marker = '  _ProviderInfo? _providerFrom(BindingCall binding) {\n'
    helper = '''  BetterEffectProviderLifetime _bindingLifetime(
    BindingCall binding,
  ) {
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

'''
    replace_once(marker, helper + marker, 'provider lifetime helper')

provider_constructor = '''    required this.inlineDependencies,
    required this.isResource,
'''
if 'required this.lifetime' not in source:
    replace_once(
        provider_constructor,
        '''    required this.inlineDependencies,
    required this.lifetime,
    required this.isResource,
''',
        'provider lifetime constructor',
    )
    replace_once(
        '''  final Set<_ServiceRef> inlineDependencies;
  final bool isResource;
''',
        '''  final Set<_ServiceRef> inlineDependencies;
  final BetterEffectProviderLifetime lifetime;
  final bool isResource;
''',
        'provider lifetime field',
    )

path.write_text(source)
