import 'graph_model.dart';

/// Raised when a graph selector is missing or ambiguous.
final class BetterEffectGraphSelectionException implements Exception {
  const BetterEffectGraphSelectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One dependency path inside a selected Module environment.
final class BetterEffectDependencyPath {
  BetterEffectDependencyPath({
    required this.moduleId,
    required Iterable<String> serviceIds,
  }) : serviceIds = List<String>.unmodifiable(serviceIds);

  final String moduleId;
  final List<String> serviceIds;

  Map<String, Object> toJson() => <String, Object>{
    'moduleId': moduleId,
    'serviceIds': serviceIds,
  };
}

/// Explanation of one effective Module environment.
final class BetterEffectModuleExplanation {
  BetterEffectModuleExplanation({
    required this.module,
    required Iterable<BetterEffectGraphProvider> providers,
    required Iterable<BetterEffectGraphDependency> dependencies,
    required Iterable<BetterEffectGraphService> externalRequirements,
    required Iterable<BetterEffectGraphDiagnostic> diagnostics,
  }) : providers = List<BetterEffectGraphProvider>.unmodifiable(providers),
       dependencies = List<BetterEffectGraphDependency>.unmodifiable(
         dependencies,
       ),
       externalRequirements = List<BetterEffectGraphService>.unmodifiable(
         externalRequirements,
       ),
       diagnostics = List<BetterEffectGraphDiagnostic>.unmodifiable(diagnostics);

  final BetterEffectGraphModule module;
  final List<BetterEffectGraphProvider> providers;
  final List<BetterEffectGraphDependency> dependencies;
  final List<BetterEffectGraphService> externalRequirements;
  final List<BetterEffectGraphDiagnostic> diagnostics;

  Map<String, Object> toJson() => <String, Object>{
    'module': module.toJson(),
    'providers': <Object>[
      for (final provider in providers) provider.toJson(),
    ],
    'dependencies': <Object>[
      for (final dependency in dependencies) dependency.toJson(),
    ],
    'externalRequirements': <Object>[
      for (final service in externalRequirements) service.toJson(),
    ],
    'diagnostics': <Object>[
      for (final diagnostic in diagnostics) diagnostic.toJson(),
    ],
  };
}

/// Declarations proven unreachable from explicit complete composition roots.
final class BetterEffectUnusedResult {
  BetterEffectUnusedResult({
    required Iterable<BetterEffectGraphModule> modules,
    required Iterable<BetterEffectGraphProvider> providers,
  }) : modules = List<BetterEffectGraphModule>.unmodifiable(modules),
       providers = List<BetterEffectGraphProvider>.unmodifiable(providers);

  final List<BetterEffectGraphModule> modules;
  final List<BetterEffectGraphProvider> providers;

  bool get isEmpty => modules.isEmpty && providers.isEmpty;

  Map<String, Object> toJson() => <String, Object>{
    'modules': <Object>[for (final module in modules) module.toJson()],
    'providers': <Object>[
      for (final provider in providers) provider.toJson(),
    ],
  };
}

/// Public query helpers over a [BetterEffectGraph].
extension BetterEffectGraphQueries on BetterEffectGraph {
  /// Resolve a Module by stable ID or unique display name.
  BetterEffectGraphModule resolveModule(String selector) {
    final direct = modulesById[selector];
    if (direct != null) return direct;

    final matches = modules
        .where((module) => module.name == selector)
        .toList(growable: false);
    if (matches.isEmpty) {
      throw BetterEffectGraphSelectionException(
        "Module '$selector' was not found. Available Modules: "
        '${modules.map((module) => module.name).toSet().toList()..sort()}.',
      );
    }
    if (matches.length > 1) {
      final candidates = matches
          .map(
            (module) =>
                '${module.id} (${module.location.path}:${module.location.line})',
          )
          .toList()
        ..sort();
      throw BetterEffectGraphSelectionException(
        "Module '$selector' is ambiguous. Use one of: "
        '${candidates.join(', ')}.',
      );
    }
    return matches.single;
  }

  /// Resolve a service by stable ID, unique display type or `Type[key]` selector.
  BetterEffectGraphService resolveService(String selector) {
    final direct = servicesById[selector];
    if (direct != null) return direct;

    final matches = services
        .where(
          (service) =>
              service.display == selector || service.selector == selector,
        )
        .toList(growable: false);
    if (matches.isEmpty) {
      final available = services.map((service) => service.selector).toSet().toList()
        ..sort();
      throw BetterEffectGraphSelectionException(
        "Service '$selector' was not found. Available services: $available.",
      );
    }
    if (matches.length > 1) {
      final candidates = matches.map((service) => service.id).toList()..sort();
      throw BetterEffectGraphSelectionException(
        "Service '$selector' is ambiguous. Use a keyed selector or stable ID: "
        '${candidates.join(', ')}.',
      );
    }
    return matches.single;
  }

  /// Effective providers, requirements and diagnostics for one Module.
  BetterEffectModuleExplanation explainModule(String selector) {
    final module = resolveModule(selector);
    final providers = <BetterEffectGraphProvider>[
      for (final id in module.providerIds)
        if (providersById[id] case final provider?) provider,
    ]..sort((left, right) => left.serviceId.compareTo(right.serviceId));
    final dependencyIds = <String>{
      for (final provider in providers) ...provider.dependencyIds,
    };
    final dependencies = <BetterEffectGraphDependency>[
      for (final id in dependencyIds)
        if (dependenciesById[id] case final dependency?) dependency,
    ]..sort((left, right) => left.id.compareTo(right.id));
    final providedServices = providers.map((provider) => provider.serviceId).toSet();
    final external = <BetterEffectGraphService>[
      for (final dependency in dependencies)
        if (!providedServices.contains(dependency.serviceId))
          if (servicesById[dependency.serviceId] case final service?) service,
    ];
    final uniqueExternal = <String, BetterEffectGraphService>{
      for (final service in external) service.id: service,
    }.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    final relatedPaths = <String>{
      module.location.path,
      for (final provider in providers) provider.location.path,
    };
    final relatedDiagnostics = diagnostics
        .where((diagnostic) => relatedPaths.contains(diagnostic.location.path))
        .toList()
      ..sort((left, right) => left.location.compareTo(right.location));

    return BetterEffectModuleExplanation(
      module: module,
      providers: providers,
      dependencies: dependencies,
      externalRequirements: uniqueExternal,
      diagnostics: relatedDiagnostics,
    );
  }

  /// Explain why [serviceSelector] is required from selected root Modules.
  ///
  /// When [moduleSelectors] is empty, every explicit, selected, or inferred root
  /// is used. All shortest acyclic paths are returned deterministically.
  List<BetterEffectDependencyPath> whyService(
    String serviceSelector, {
    Iterable<String> moduleSelectors = const <String>[],
  }) {
    final target = resolveService(serviceSelector);
    final selectedModules = moduleSelectors.isEmpty
        ? <BetterEffectGraphModule>[
            for (final id in rootModuleIds)
              if (modulesById[id] case final module?) module,
          ]
        : <BetterEffectGraphModule>[
            for (final selector in moduleSelectors) resolveModule(selector),
          ];
    final paths = <BetterEffectDependencyPath>[];

    for (final module in selectedModules) {
      paths.addAll(_whyInModule(module, target.id));
    }

    paths.sort((left, right) {
      final moduleOrder = left.moduleId.compareTo(right.moduleId);
      if (moduleOrder != 0) return moduleOrder;
      return left.serviceIds.join('\u0000').compareTo(
        right.serviceIds.join('\u0000'),
      );
    });
    return List<BetterEffectDependencyPath>.unmodifiable(paths);
  }

  /// Return only declarations proven unreachable from explicit complete roots.
  ///
  /// No unused finding is produced when the project has only inferred roots,
  /// because an unreferenced Module can itself be an application entry point.
  BetterEffectUnusedResult unusedDeclarations() {
    final modules = <BetterEffectGraphModule>[
      for (final id in unreachableModuleIds)
        if (modulesById[id] case final module?) module,
    ]..sort((left, right) => left.id.compareTo(right.id));
    final providers = <BetterEffectGraphProvider>[
      for (final id in unreachableProviderIds)
        if (providersById[id] case final provider?) provider,
    ]..sort((left, right) => left.id.compareTo(right.id));

    return BetterEffectUnusedResult(modules: modules, providers: providers);
  }

  List<BetterEffectDependencyPath> _whyInModule(
    BetterEffectGraphModule module,
    String targetServiceId,
  ) {
    final providers = <BetterEffectGraphProvider>[
      for (final id in module.providerIds)
        if (providersById[id] case final provider?) provider,
    ];
    final byService = <String, BetterEffectGraphProvider>{
      for (final provider in providers) provider.serviceId: provider,
    };
    if (!byService.containsKey(targetServiceId)) return const [];

    final required = <String>{
      for (final provider in providers)
        for (final dependencyId in provider.dependencyIds)
          if (dependenciesById[dependencyId] case final dependency?)
            if (dependency.isResolved) dependency.serviceId,
    };
    final entries = providers
        .where((provider) => !required.contains(provider.serviceId))
        .map((provider) => provider.serviceId)
        .toList()
      ..sort();
    if (entries.isEmpty) {
      entries.addAll(byService.keys.toList()..sort());
    }

    final paths = <BetterEffectDependencyPath>[];
    final queue = <List<String>>[
      for (final entry in entries) <String>[entry],
    ];
    var shortestLength = 1 << 30;

    while (queue.isNotEmpty) {
      final path = queue.removeAt(0);
      if (path.length > shortestLength) continue;
      final current = path.last;

      if (current == targetServiceId) {
        shortestLength = path.length;
        paths.add(
          BetterEffectDependencyPath(
            moduleId: module.id,
            serviceIds: path,
          ),
        );
        continue;
      }

      final provider = byService[current];
      if (provider == null) continue;
      final nextServices = <String>[
        for (final dependencyId in provider.dependencyIds)
          if (dependenciesById[dependencyId] case final dependency?)
            if (dependency.isResolved) dependency.serviceId,
      ]..sort();

      for (final next in nextServices) {
        if (!path.contains(next)) {
          queue.add(<String>[...path, next]);
        }
      }
    }

    return paths;
  }
}
