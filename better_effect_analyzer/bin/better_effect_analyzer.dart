import 'dart:io';

import 'package:args/args.dart';
import 'package:better_effect_analyzer/better_effect_analyzer.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show command usage.',
    )
    ..addFlag(
      'include-tests',
      negatable: false,
      help: 'Include the test directory in the graph index.',
    )
    ..addMultiOption(
      'module',
      abbr: 'm',
      help:
          'Check only the named root Module. Repeat for multiple Modules.',
      valueHelp: 'name',
    )
    ..addOption(
      'format',
      allowed: const <String>['human', 'machine', 'json'],
      defaultsTo: 'human',
      help: 'Diagnostic output format.',
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
    stderr.writeln(error.message);
    stderr.writeln(_usage(parser));
    exitCode = 64;
    return;
  }

  if (results.flag('help')) {
    stdout.writeln(_usage(parser));
    return;
  }

  final rest = results.rest;
  if (rest.length > 1) {
    stderr.writeln('Only one project path can be checked at a time.');
    stderr.writeln(_usage(parser));
    exitCode = 64;
    return;
  }

  final root = rest.isEmpty ? Directory.current.path : rest.single;
  final checker = BetterEffectGraphChecker(root);

  late final GraphCheckResult result;
  try {
    result = await checker.check(
      options: GraphCheckOptions(
        includeTests: results.flag('include-tests'),
        moduleNames: results.multiOption('module').toSet(),
      ),
    );
  } catch (error, stackTrace) {
    stderr.writeln('better_effect_analyzer failed: $error');
    if (results.option('format') == 'human') {
      stderr.writeln(stackTrace);
    }
    exitCode = 70;
    return;
  }

  final format = results.option('format');
  if (format == 'json') {
    stdout.writeln(result.toJson());
  } else if (format == 'machine') {
    for (final diagnostic in result.diagnostics) {
      stdout.writeln(diagnostic.toMachine());
    }
  } else {
    _printHuman(result);
  }

  final fatalWarnings = results.flag('fatal-warnings');
  if (result.hasErrors || (fatalWarnings && result.hasWarnings)) {
    exitCode = 1;
  }
}

void _printHuman(GraphCheckResult result) {
  if (result.diagnostics.isEmpty) {
    stdout.writeln('No better_effect graph issues found.');
    return;
  }

  for (final diagnostic in result.diagnostics) {
    stdout.writeln(
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

  stdout
    ..writeln()
    ..writeln('$errors error(s), $warnings warning(s), $infos info(s).');
}

String _usage(ArgParser parser) {
  return '''
Validate a better_effect Module graph across a Dart or Flutter package.

Usage:
  dart run better_effect_analyzer [options] [project-path]

Options:
${parser.usage}
'''.trim();
}
