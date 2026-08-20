import 'dart:io';

import 'package:better_effect_analyzer/better_effect_analyzer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('--schema-version does not require a project analysis', () async {
    final executable = p.join(
      Directory.current.path,
      'bin',
      'better_effect_analyzer.dart',
    );
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      executable,
      '--schema-version',
    ]);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout.toString().trim(), '$betterEffectGraphSchemaVersion');
    expect(result.stderr.toString(), isEmpty);
  });

  test('--schema-version can be written to an output file', () async {
    final temporary = Directory.systemTemp.createTempSync(
      'better_effect_schema_version_',
    );
    addTearDown(() => temporary.deleteSync(recursive: true));
    final output = File(p.join(temporary.path, 'schema-version.txt'));
    final executable = p.join(
      Directory.current.path,
      'bin',
      'better_effect_analyzer.dart',
    );
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      executable,
      '--schema-version',
      '--output',
      output.path,
    ]);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(output.readAsStringSync().trim(), '$betterEffectGraphSchemaVersion');
  });
}
