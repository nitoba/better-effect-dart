import 'dart:io';

import 'package:args/args.dart';
import 'package:better_effect_analyzer/better_effect_analyzer.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show command usage.')
    ..addFlag(
      'include-tests',
      negatable: false,
      help: 'Include the test directory in the graph index.',
    )
    ..addMultiOption(
      'module',
      abbr: 'm',
      help: 'Select a root Module. Repeat for multiple Modules.',
      valueHelp: 'name',
    )
    ..addOption(
      'format',
      allowed: const <String>[
        'human',
        'text',
        'machine',
        'json',
        'sarif',
        'dot',
        'mermaid',
      ],
      defaultsTo: 'human',
      help: 'Diagnostic, graph, or inspection output format.',
    )
    ..addOption(
      'output',
      abbr: 'o',
      help: 'Write output to a file instead of stdout.',
      valueHelp: 'path',
    )
    ..addFlag(
      'graph',
      negatable: false,
      help: 'Export the reusable dependency graph.',
    )
    ..addOption(
      'explain',
      help: 'Explain providers and requirements for one Module.',
      valueHelp: 'module',
    )
    ..addOption(
      'why',
      help: 'Show why a service is required by the selected roots.',
      valueHelp: 'service-or-id',
    )
    ..addFlag(
      'unused',
      negatable: false,
      help: 'Report declarations proven unreachable from complete roots.',
    )
    ..addFlag(
      'fatal-warnings',
      defaultsTo: true,
      help: 'Return a non-zero exit code when warnings are reported.',
    );

  late final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (error) {
    _usageError(error.message, parser);
    return;
  }

  if (results.flag('help')) {
    stdout.writeln(_usage(parser));
    return;
  }

  final rest = results.rest;
  if (rest.length > 1) {
    _usageError('Only one project path can be checked at a time.', parser);
    return;
  }

  final queryCount = <bool>[
    results.flag('graph'),
    results.option('explain') != null,
    results.option('why') != null,
    results.flag('unused'),
  ].where((selected) => selected).length;
  if (queryCount > 1) {
    _usageError(
      'Use only one of --graph, --explain, --why, or --unused.',
      parser,
    );
    return;
  }

  final root = rest.isEmpty ? Directory.current.path : rest.single;
  final checker = BetterEffectGraphChecker(root);

  late final BetterEffectGraphAnalysis analysis;
  try {
    analysis = await checker.analyze(
      options: GraphCheckOptions(
        includeTests: results.flag('include-tests'),
        moduleNames: results.multiOption('module').toSet(),
      ),
    );
  } catch (error, stackTrace) {
    stderr.writeln('better_effect_analyzer failed: $error');
    if (_isTextFormat(results.option('format'))) {
      stderr.writeln(stackTrace);
    }
    exitCode = 70;
    return;
  }

  final formatName = results.option('format')!;
  late final String rendered;
  try {
    rendered = _render(results, analysis, formatName);
  } on BetterEffectGraphSelectionException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  } on ArgumentError catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }

  final outputPath = results.option('output');
  if (outputPath == null) {
    stdout.writeln(rendered);
  } else {
    final output = File(outputPath);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync('$rendered\n');
  }

  final fatalWarnings = results.flag('fatal-warnings');
  if (analysis.hasErrors || (fatalWarnings && analysis.hasWarnings)) {
    exitCode = 1;
  }
}

String _render(
  ArgResults results,
  BetterEffectGraphAnalysis analysis,
  String formatName,
) {
  final graph = analysis.graph;
  final explain = results.option('explain');
  final why = results.option('why');
  final unused = results.flag('unused');
  final graphRequested = results.flag('graph') ||
      formatName == 'dot' ||
      formatName == 'mermaid';

  if (explain != null) {
    final format = _inspectionFormat(formatName);
    return BetterEffectGraphRenderer.explain(
      graph,
      graph.explainModule(explain),
      format: format,
    );
  }

  if (why != null) {
    final format = _inspectionFormat(formatName);
    final service = graph.resolveService(why);
    final paths = graph.whyService(
      why,
      moduleSelectors: results.multiOption('module'),
    );
    return BetterEffectGraphRenderer.why(
      graph,
      service,
      paths,
      format: format,
    );
  }

  if (unused) {
    return BetterEffectGraphRenderer.unused(
      graph,
      graph.unusedDeclarations(),
      format: _inspectionFormat(formatName),
    );
  }

  if (graphRequested) {
    if (formatName == 'machine' || formatName == 'sarif') {
      throw ArgumentError(
        'Graph export supports text, JSON, DOT, or Mermaid output.',
      );
    }
    return BetterEffectGraphRenderer.graph(
      graph,
      format: _graphFormat(formatName),
    );
  }

  if (formatName == 'sarif') {
    return BetterEffectGraphRenderer.sarif(analysis.diagnostics);
  }
  if (formatName == 'json') {
    // Preserve the existing diagnostic JSON shape when no graph command is used.
    return analysis.checkResult.toJson();
  }
  if (formatName == 'machine') {
    return analysis.diagnostics
        .map((diagnostic) => diagnostic.toMachine())
        .join('\n');
  }

  return _humanDiagnostics(analysis.checkResult);
}

BetterEffectGraphFormat _inspectionFormat(String name) {
  return switch (name) {
    'human' || 'text' => BetterEffectGraphFormat.text,
    'json' => BetterEffectGraphFormat.json,
    _ => throw ArgumentError(
        'Inspection commands support text or JSON output.',
      ),
  };
}

BetterEffectGraphFormat _graphFormat(String name) {
  return switch (name) {
    'human' || 'text' => BetterEffectGraphFormat.text,
    'json' => BetterEffectGraphFormat.json,
    'dot' => BetterEffectGraphFormat.dot,
    'mermaid' => BetterEffectGraphFormat.mermaid,
    _ => throw ArgumentError(
        'Graph export supports text, JSON, DOT, or Mermaid output.',
      ),
  };
}

bool _isTextFormat(String? name) => name == 'human' || name == 'text';

String _humanDiagnostics(GraphCheckResult result) {
  if (result.diagnostics.isEmpty) {
    return 'No better_effect graph issues found.';
  }

  final buffer = StringBuffer();
  for (final diagnostic in result.diagnostics) {
    buffer.writeln(
      '${diagnostic.severity.name.padRight(7)} '
      '${diagnostic.path}:${diagnostic.line}:${diagnostic.column} '
      '[${diagnostic.code}] ${diagnostic.message}',
    );
  }

  final errors = result.diagnostics
      .where((item) => item.severity == GraphDiagnosticSeverity.error)
      .length;
  final warnings = result.diagnostics
      .where((item) => item.severity == GraphDiagnosticSeverity.warning)
      .length;
  final infos = result.diagnostics
      .where((item) => item.severity == GraphDiagnosticSeverity.info)
      .length;

  buffer
    ..writeln()
    ..write('$errors error(s), $warnings warning(s), $infos info(s).');
  return buffer.toString();
}

void _usageError(String message, ArgParser parser) {
  stderr
    ..writeln(message)
    ..writeln(_usage(parser));
  exitCode = 64;
}

String _usage(ArgParser parser) {
  return '''
Validate and inspect a better_effect Module graph across a Dart or Flutter package.

Usage:
  dart run better_effect_analyzer [options] [project-path]

Examples:
  dart run better_effect_analyzer --graph --format json > graph.json
  dart run better_effect_analyzer --format sarif --output build/graph.sarif
  dart run better_effect_analyzer --explain appModule
  dart run better_effect_analyzer --why UserRepository
  dart run better_effect_analyzer --unused

Options:
${parser.usage}
'''
      .trim();
}
