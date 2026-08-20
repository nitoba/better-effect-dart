import 'dart:collection';

/// Version of the serialized better_effect graph contract.
///
/// Consumers must reject a greater major version that they do not understand.
const betterEffectGraphSchemaVersion = 1;

/// Runtime lifetime represented by a provider in the dependency graph.
enum BetterEffectProviderLifetime {
  factory,
  singleton,
  lazySingleton,
  instance,
  resource,
  unknown,
}

/// How one provider requires another service.
enum BetterEffectDependencyKind {
  constructor,
  contextual,
  resource,
}

/// Why a Module is selected as a graph root.
enum BetterEffectGraphRootKind {
  complete,
  inferred,
  selected,
}

/// Severity copied into the serializable graph model.
enum BetterEffectGraphDiagnosticSeverity { info, warning, error }

/// Stable source position attached to graph entities.
final class BetterEffectGraphLocation implements Comparable<BetterEffectGraphLocation> {
  const BetterEffectGraphLocation({
    required this.path,
    required this.line,
    required this.column,
    required this.length,
  });

  final String path;
  final int line;
  final int column;
  final int length;

  Map<String, Object> toJson() => <String, Object>{
    'path': path,
    'line': line,
    'column': column,
    'length': length,
  };

  @override
  int compareTo(BetterEffectGraphLocation other) {
    final pathOrder = path.compareTo(other.path);
    if (pathOrder != 0) return pathOrder;
    final lineOrder = line.compareTo(other.line);
    if (lineOrder != 0) return lineOrder;
    final columnOrder = column.compareTo(other.column);
    if (columnOrder != 0) return columnOrder;
    return length.compareTo(other.length);
  }
}

/// Diagnostic projection independent from analyzer AST and element objects.
final class BetterEffectGraphDiagnostic {
  const BetterEffectGraphDiagnostic({
    required this.code,
    required this.message,
    required this.severity,
    required this.location,
  });

  final String code;
  final String message;
  final BetterEffectGraphDiagnosticSeverity severity;
  final BetterEffectGraphLocation location;

  Map<String, Object> toJson() => <String, Object>{
    'code': code,
    'message': message,
    'severity': severity.name,
    'location': location.toJson(),
  };
}

/// One typed service identity, including an optional [ServiceKey] identity.
final class BetterEffectGraphService {
  const BetterEffectGraphService({
    required this.id,
    required this.display,
    required this.typeId,
    required this.keyId,
    required this.keyName,
  });

  /// Stable identity composed from the resolved type and key identity.
  final String id;

  /// Human-readable Dart type.
  final String display;

  /// Stable resolved type identity.
  final String typeId;

  /// Stable key identity used to match providers and requests.
  final String keyId;

  /// Human-oriented key name when it can be resolved statically.
  final String? keyName;

  bool get isKeyed => keyId != '<default>';

  /// Selector accepted by `--why` when the display type is ambiguous.
  String get selector => keyName == null ? display : '$display[$keyName]';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'display': display,
    'typeId': typeId,
    'keyId': keyId,
    'keyName': keyName,
    'selector': selector,
  };
}

/// A dependency edge from one provider to a required service.
final class BetterEffectGraphDependency {
  const BetterEffectGraphDependency({
    required this.id,
    required this.providerId,
    required this.serviceId,
    required this.kind,
    required this.isResolved,
    required this.location,
  });

  final String id;
  final String providerId;
  final String serviceId;
  final BetterEffectDependencyKind kind;

  /// Whether the selected Module environment provides [serviceId].
  final bool isResolved;

  final BetterEffectGraphLocation? location;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'providerId': providerId,
    'serviceId': serviceId,
    'kind': kind.name,
    'isResolved': isResolved,
    'location': location?.toJson(),
  };
}

/// One effective provider inside a Module environment.
///
/// Providers are projected per Module environment. A reusable provider included
/// in two roots therefore has one effective provider per root, allowing
/// overrides to be represented without losing source location.
final class BetterEffectGraphProvider {
  BetterEffectGraphProvider({
    required this.id,
    required this.moduleId,
    required this.declaredModuleId,
    required this.serviceId,
    required this.serviceDisplay,
    required this.implementationDisplay,
    required this.lifetime,
    required this.isResource,
    required this.location,
    required Iterable<String> dependencyIds,
  }) : dependencyIds = List<String>.unmodifiable(dependencyIds);

  final String id;

  /// Environment in which this provider is effective.
  final String moduleId;

  /// Module declaration that originally contributed the binding.
  final String declaredModuleId;

  final String serviceId;
  final String serviceDisplay;
  final String? implementationDisplay;
  final BetterEffectProviderLifetime lifetime;
  final bool isResource;
  final BetterEffectGraphLocation location;
  final List<String> dependencyIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'moduleId': moduleId,
    'declaredModuleId': declaredModuleId,
    'serviceId': serviceId,
    'serviceDisplay': serviceDisplay,
    'implementationDisplay': implementationDisplay,
    'lifetime': lifetime.name,
    'isResource': isResource,
    'location': location.toJson(),
    'dependencyIds': dependencyIds,
  };
}

/// One reusable, complete, execution-scoped, or overridden Module projection.
final class BetterEffectGraphModule {
  BetterEffectGraphModule({
    required this.id,
    required this.name,
    required this.location,
    required this.isComplete,
    required this.isExecutionOverlay,
    required this.isOverride,
    required this.rootKind,
    required this.baseModuleId,
    required Iterable<String> includedModuleIds,
    required Iterable<String> declaredProviderIds,
    required Iterable<String> providerIds,
  }) : includedModuleIds = List<String>.unmodifiable(includedModuleIds),
       declaredProviderIds = List<String>.unmodifiable(declaredProviderIds),
       providerIds = List<String>.unmodifiable(providerIds);

  final String id;
  final String name;
  final BetterEffectGraphLocation location;
  final bool isComplete;
  final bool isExecutionOverlay;
  final bool isOverride;
  final BetterEffectGraphRootKind? rootKind;
  final String? baseModuleId;
  final List<String> includedModuleIds;

  /// Providers declared directly in this Module.
  final List<String> declaredProviderIds;

  /// Providers effective after merge and override expansion.
  final List<String> providerIds;

  bool get isRoot => rootKind != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'location': location.toJson(),
    'isComplete': isComplete,
    'isExecutionOverlay': isExecutionOverlay,
    'isOverride': isOverride,
    'rootKind': rootKind?.name,
    'baseModuleId': baseModuleId,
    'includedModuleIds': includedModuleIds,
    'declaredProviderIds': declaredProviderIds,
    'providerIds': providerIds,
  };
}

/// Deterministic, serializable dependency graph for one analyzed package.
final class BetterEffectGraph {
  BetterEffectGraph({
    required this.projectName,
    required this.rootPath,
    required Iterable<String> rootModuleIds,
    required Iterable<BetterEffectGraphModule> modules,
    required Iterable<BetterEffectGraphService> services,
    required Iterable<BetterEffectGraphProvider> providers,
    required Iterable<BetterEffectGraphDependency> dependencies,
    required Iterable<BetterEffectGraphDiagnostic> diagnostics,
    required Iterable<String> unreachableModuleIds,
    required Iterable<String> unreachableProviderIds,
  }) : rootModuleIds = List<String>.unmodifiable(rootModuleIds),
       modules = List<BetterEffectGraphModule>.unmodifiable(modules),
       services = List<BetterEffectGraphService>.unmodifiable(services),
       providers = List<BetterEffectGraphProvider>.unmodifiable(providers),
       dependencies = List<BetterEffectGraphDependency>.unmodifiable(
         dependencies,
       ),
       diagnostics = List<BetterEffectGraphDiagnostic>.unmodifiable(diagnostics),
       unreachableModuleIds = List<String>.unmodifiable(unreachableModuleIds),
       unreachableProviderIds = List<String>.unmodifiable(
         unreachableProviderIds,
       ),
       modulesById = UnmodifiableMapView<String, BetterEffectGraphModule>(
         <String, BetterEffectGraphModule>{
           for (final module in modules) module.id: module,
         },
       ),
       servicesById = UnmodifiableMapView<String, BetterEffectGraphService>(
         <String, BetterEffectGraphService>{
           for (final service in services) service.id: service,
         },
       ),
       providersById = UnmodifiableMapView<String, BetterEffectGraphProvider>(
         <String, BetterEffectGraphProvider>{
           for (final provider in providers) provider.id: provider,
         },
       ),
       dependenciesById =
           UnmodifiableMapView<String, BetterEffectGraphDependency>(
             <String, BetterEffectGraphDependency>{
               for (final dependency in dependencies)
                 dependency.id: dependency,
             },
           );

  final String projectName;

  /// Absolute path in the embedded API. Serialized locations remain relative.
  final String rootPath;

  final List<String> rootModuleIds;
  final List<BetterEffectGraphModule> modules;
  final List<BetterEffectGraphService> services;
  final List<BetterEffectGraphProvider> providers;
  final List<BetterEffectGraphDependency> dependencies;
  final List<BetterEffectGraphDiagnostic> diagnostics;

  /// Declarations proven unreachable from explicit complete roots.
  final List<String> unreachableModuleIds;
  final List<String> unreachableProviderIds;

  final Map<String, BetterEffectGraphModule> modulesById;
  final Map<String, BetterEffectGraphService> servicesById;
  final Map<String, BetterEffectGraphProvider> providersById;
  final Map<String, BetterEffectGraphDependency> dependenciesById;

  Map<String, Object> toJson() => <String, Object>{
    'schemaVersion': betterEffectGraphSchemaVersion,
    'project': <String, Object>{
      'name': projectName,
      'root': '.',
    },
    'rootModuleIds': rootModuleIds,
    'modules': <Object>[for (final module in modules) module.toJson()],
    'services': <Object>[for (final service in services) service.toJson()],
    'providers': <Object>[for (final provider in providers) provider.toJson()],
    'dependencies': <Object>[
      for (final dependency in dependencies) dependency.toJson(),
    ],
    'diagnostics': <Object>[
      for (final diagnostic in diagnostics) diagnostic.toJson(),
    ],
    'unreachable': <String, Object>{
      'moduleIds': unreachableModuleIds,
      'providerIds': unreachableProviderIds,
    },
  };
}
