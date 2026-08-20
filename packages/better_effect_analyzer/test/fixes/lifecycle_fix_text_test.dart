import 'package:better_effect_analyzer/src/support/lifecycle_fix_text.dart';
import 'package:test/test.dart';

void main() {
  test('await execution fix observes Exit', () {
    expect(
      awaitExecutionReplacement('runtime.execute(effect)'),
      'await (runtime.execute(effect)).exit',
    );
  });

  test('return execution fix preserves the Future<Exit> boundary', () {
    expect(
      returnExecutionReplacement('runtime.execute(effect)'),
      'return (runtime.execute(effect)).exit;',
    );
  });

  test('own Command fix uses the existing ViewModel owner', () {
    expect(
      ownCommandReplacement('commands(loadUsers)'),
      'ownCommand(commands(loadUsers))',
    );
  });

  test('Runtime ownership fix preserves nested statement indentation', () {
    expect(
      runtimeTryFinallyReplacement(
        statements: 'await work();\n  if (ready) {\n    publish();\n  }',
        indentation: '  ',
        oneIndent: '  ',
        runtimeName: 'runtime',
      ),
      '''try {
    await work();
    if (ready) {
      publish();
    }
  } finally {
    await runtime.close();
  }''',
    );
  });
}
