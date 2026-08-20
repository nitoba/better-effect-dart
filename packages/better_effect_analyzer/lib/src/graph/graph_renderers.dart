import 'dart:convert';

import 'graph_checker.dart';
import 'graph_model.dart';
import 'graph_queries.dart';

/// Supported public graph and diagnostic export formats.
enum BetterEffectGraphFormat { text, json, sarif, dot, mermaid }

/// Deterministic rendering helpers for graph exports and inspection results.
final class BetterEffectGraphRenderer {
  const BetterEffectGraphRenderer._();

  static String graph(
    BetterEffectGraph graph, {
    BetterEffectGraphFormat format = BetterEffectGraphFormat.text,
  }) {
    return switch (format) {
      BetterEffectGraphFormat.text => _graphText(graph),
      BetterEffectGraphFormat.json => _json(graph.toJson()),
      BetterEffectGraphFormat.dot => _dot(graph),
      BetterEffectGraphFormat.mermaid => _mermaid(graph),
      BetterEffectGraphFormat.sarif => throw ArgumentError(
        'SARIF represents diagnostics. Use BetterEffectGraphRenderer.sarif().',
      ),
    };
  }

  static String explain(
    BetterEffectGraph graph,
    BetterEffectModuleExplanation explanation, {
    BetterEffectGraphFormat format = BetterEffectGraphFormat.text,
  }) {
    return switch (format) {
      BetterEffectGraphFormat.text => _explainText(graph, explanation),
      BetterEffectGraphFormat.json => _json(<String, Object>{
        'schemaVersion': betterEffectGraphSchemaVersion,
        'query': 'explain',
        'result': explanation.toJson(),
      }),
      _ => throw ArgumentError(
        'Module explanation supports text or JSON output.',
      ),
    };
  }

  static String why(
    BetterEffectGraph graph,
    BetterEffectGraphService service,
    Iterable<BetterEffectDependencyPath> paths, {
    BetterEffectGraphFormat format = BetterEffectGraphFormat.text,
  }) {
    final values = List<BetterEffectDependencyPath>.of(paths);
    return switch (format) {
      BetterEffectGraphFormat.text => _whyText(graph, service, values),
      BetterEffectGraphFormat.json => _json(<String, Object>{
        'schemaVersion': betterEffectGraphSchemaVersion,
        'query': 'why',
        'service': service.toJson(),
        'paths': <Object>[for (final path in values) path.toJson()],
      }),
      _ => throw ArgumentError('Why queries support text or JSON output.'),
    };
  }

  static String unused(
    BetterEffectGraph graph,
    BetterEffectUnusedResult result, {
    BetterEffectGraphFormat format = BetterEffectGraphFormat.text,
  }) {
    return switch (format) {
      BetterEffectGraphFormat.text => _unusedText(graph, result),
      BetterEffectGraphFormat.json => _json(<String, Object>{
        'schemaVersion': betterEffectGraphSchemaVersion,
        'query': 'unused',
        'proofBoundary':
            'Only declarations unreachable from explicit complete roots are reported.',
        'result': result.toJson(),
      }),
      _ => throw ArgumentError('Unused queries support text or JSON output.'),
    };
  }

  /// Render diagnostics as a SARIF 2.1.0 document suitable for code scanning.
  static String sarif(Iterable<GraphDiagnostic> diagnostics) {
    final values = List<GraphDiagnostic>.of(diagnostics)
      ..sort(_diagnosticOrder);
    final rules = <String, GraphDiagnostic>{
      for (final diagnostic in values) diagnostic.code: diagnostic,
    };
    final orderedRules = rules.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));

    return _json(<String, Object>{
      r'$schema': 'https://json.schemastore.org/sarif-2.1.0.json',
      'version': '2.1.0',
      'runs': <Object>[
        <String, Object>{
          'tool': <String, Object>{
            'driver': <String, Object>{
              'name': 'better_effect_analyzer',
              'informationUri':
                  'https://pub.dev/packages/better_effect_analyzer',
              'rules': <Object>[
                for (final entry in orderedRules)
                  <String, Object>{
                    'id': entry.key,
                    'name': entry.key,
                    'shortDescription': <String, String>{
                      'text': entry.value.message,
                    },
                    'defaultConfiguration': <String, String>{
                      'level': _sarifLevel(entry.value.severity),
                    },
                  },
              ],
            },
          },
          'results': <Object>[
            for (final diagnostic in values)
              <String, Object>{
                'ruleId': diagnostic.code,
                'level': _sarifLevel(diagnostic.severity),
                'message': <String, String>{'text': diagnostic.message},
                'locations': <Object>[
                  <String, Object>{
                    'physicalLocation': <String, Object>{
                      'artifactLocation': <String, String>{
                        'uri': diagnostic.path,
                      },
                      'region': <String, int>{
                        'startLine': diagnostic.line,
                        'startColumn': diagnostic.column,
                        'endColumn': diagnostic.column + diagnostic.length,
                      },
                    },
                  },
                ],
              },
          ],
        },
      ],
    });
  }

  static String _json(Object value) {
    return const JsonEncoder.withIndent('  ').convert(value);
  }

  static String _graphText(BetterEffectGraph graph) {
    final buffer = StringBuffer()
      ..writeln('better_effect graph schema $betterEffectGraphSchemaVersion')
      ..writeln('project: ${graph.projectName}')
      ..writeln(
        'modules: ${graph.modules.length}, services: ${graph.services.length}, '
        'providers: ${graph.providers.length}, '
        'dependencies: ${graph.dependencies.length}',
      );

    for (final module in graph.modules) {
      final markers = <String>[
        if (module.rootKind != null) 'root:${module.rootKind!.name}',
        if (module.isComplete) 'complete',
        if (module.isExecutionOverlay) 'execution',
        if (module.isOverride) 'override',
        if (graph.unreachableModuleIds.contains(module.id)) 'unreachable',
      ];
      buffer
        ..writeln()
        ..writeln(
          '${module.name}${markers.isEmpty ? '' : ' [${markers.join(', ')}]'}',
        )
        ..writeln('  id: ${module.id}')
        ..writeln(
          '  source: ${module.location.path}:'
          '${module.location.line}:${module.location.column}',
        );

      for (final providerId in module.providerIds) {
        final provider = graph.providersById[providerId];
        if (provider == null) continue;
        final requirements = <String>[
          for (final dependencyId in provider.dependencyIds)
            if (graph.dependenciesById[dependencyId] case final dependency?)
              graph.servicesById[dependency.serviceId]?.selector ??
                  dependency.serviceId,
        ];
        buffer.writeln(
          '  - ${provider.serviceDisplay} '
          '(${provider.lifetime.name})'
          '${requirements.isEmpty ? '' : ' -> ${requirements.join(', ')}'}',
        );
      }
    }

    return buffer.toString().trimRight();
  }

  static String _explainText(
    BetterEffectGraph graph,
    BetterEffectModuleExplanation explanation,
  ) {
    final module = explanation.module;
    final buffer = StringBuffer()
      ..writeln('${module.name} (${module.id})')
      ..writeln(
        'source: ${module.location.path}:'
        '${module.location.line}:${module.location.column}',
      )
      ..writeln('root: ${module.rootKind?.name ?? 'no'}')
      ..writeln('complete: ${module.isComplete}')
      ..writeln('execution overlay: ${module.isExecutionOverlay}')
      ..writeln('override: ${module.isOverride}')
      ..writeln('providers:');

    for (final provider in explanation.providers) {
      final dependencies = <String>[
        for (final id in provider.dependencyIds)
          if (graph.dependenciesById[id] case final dependency?)
            graph.servicesById[dependency.serviceId]?.selector ??
                dependency.serviceId,
      ];
      buffer.writeln(
        '  ${provider.serviceDisplay} [${provider.lifetime.name}]'
        '${provider.implementationDisplay == null ? '' : ' = ${provider.implementationDisplay}'}',
      );
      if (dependencies.isNotEmpty) {
        buffer.writeln('    requires: ${dependencies.join(', ')}');
      }
    }

    if (explanation.externalRequirements.isNotEmpty) {
      buffer
        ..writeln('external requirements:')
        ..writeln(
          explanation.externalRequirements
              .map((service) => '  - ${service.selector}')
              .join('\n'),
        );
    }
    if (explanation.diagnostics.isNotEmpty) {
      buffer
        ..writeln('diagnostics:')
        ..writeln(
          explanation.diagnostics
              .map(
                (diagnostic) =>
                    '  - [${diagnostic.code}] ${diagnostic.message}',
              )
              .join('\n'),
        );
    }

    return buffer.toString().trimRight();
  }

  static String _whyText(
    BetterEffectGraph graph,
    BetterEffectGraphService service,
    List<BetterEffectDependencyPath> paths,
  ) {
    if (paths.isEmpty) {
      return "No dependency path to '${service.selector}' was found in the selected roots.";
    }

    final buffer = StringBuffer()
      ..writeln("Why '${service.selector}' is required:");
    for (final path in paths) {
      final module = graph.modulesById[path.moduleId];
      final displays = <String>[
        for (final id in path.serviceIds)
          graph.servicesById[id]?.selector ?? id,
      ];
      buffer.writeln(
        '  ${module?.name ?? path.moduleId}: ${displays.join(' -> ')}',
      );
    }
    return buffer.toString().trimRight();
  }

  static String _unusedText(
    BetterEffectGraph graph,
    BetterEffectUnusedResult result,
  ) {
    final buffer = StringBuffer()
      ..writeln(
        'Declarations unreachable from explicit complete roots:',
      );
    if (result.isEmpty) {
      buffer.writeln('  none proven');
      return buffer.toString().trimRight();
    }

    for (final module in result.modules) {
      buffer.writeln(
        '  Module ${module.name} '
        '(${module.location.path}:${module.location.line})',
      );
    }
    for (final provider in result.providers) {
      final module = graph.modulesById[provider.moduleId];
      buffer.writeln(
        '  Provider ${module?.name ?? provider.moduleId}: '
        '${provider.serviceDisplay} [${provider.lifetime.name}]',
      );
    }
    return buffer.toString().trimRight();
  }

  static String _dot(BetterEffectGraph graph) {
    final buffer = StringBuffer('digraph better_effect {\n')
      ..writeln('  rankdir=LR;')
      ..writeln('  node [shape=box];');
    final nodeIds = _stableNodeIds(graph.services);

    for (final service in graph.services) {
      buffer.writeln(
        '  ${nodeIds[service.id]} '
        '[label="${_dotEscape(service.selector)}"];',
      );
    }
    for (final provider in graph.providers) {
      final from = nodeIds[provider.serviceId];
      if (from == null) continue;
      for (final dependencyId in provider.dependencyIds) {
        final dependency = graph.dependenciesById[dependencyId];
        final to = dependency == null ? null : nodeIds[dependency.serviceId];
        if (dependency == null || to == null) continue;
        final style = dependency.isResolved ? '' : ', style=dashed';
        buffer.writeln(
          '  $from -> $to '
          '[label="${dependency.kind.name}"$style];',
        );
      }
    }
    buffer.writeln('}');
    return buffer.toString();
  }

  static String _mermaid(BetterEffectGraph graph) {
    final buffer = StringBuffer('flowchart LR\n');
    final nodeIds = _stableNodeIds(graph.services);

    for (final service in graph.services) {
      buffer.writeln(
        '  ${nodeIds[service.id]}["${_mermaidEscape(service.selector)}"]',
      );
    }
    for (final provider in graph.providers) {
      final from = nodeIds[provider.serviceId];
      if (from == null) continue;
      for (final dependencyId in provider.dependencyIds) {
        final dependency = graph.dependenciesById[dependencyId];
        final to = dependency == null ? null : nodeIds[dependency.serviceId];
        if (dependency == null || to == null) continue;
        buffer.writeln('  $from -->|${dependency.kind.name}| $to');
      }
    }
    return buffer.toString().trimRight();
  }

  static Map<String, String> _stableNodeIds(
    Iterable<BetterEffectGraphService> services,
  ) {
    final ordered = services.toList()..sort((a, b) => a.id.compareTo(b.id));
    return <String, String>{
      for (var index = 0; index < ordered.length; index++)
        ordered[index].id: 'n$index',
    };
  }

  static int _diagnosticOrder(
    GraphDiagnostic left,
    GraphDiagnostic right,
  ) => left.compareTo(right);

  static String _sarifLevel(GraphDiagnosticSeverity severity) =>
      switch (severity) {
        GraphDiagnosticSeverity.error => 'error',
        GraphDiagnosticSeverity.warning => 'warning',
        GraphDiagnosticSeverity.info => 'note',
      };

  static String _dotEscape(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n');
  }

  static String _mermaidEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\n', ' ');
  }
}
