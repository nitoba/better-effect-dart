import 'package:better_effect_analyzer/src/rules/runtime_started_without_close.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'rule_test_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(RuntimeStartedWithoutCloseTest);
  });
}

@reflectiveTest
final class RuntimeStartedWithoutCloseTest extends BetterEffectRuleTest {
  @override
  void setUp() {
    rule = RuntimeStartedWithoutCloseRule();
    super.setUp();
  }

  Future<void> test_reportsLocalRuntimeWithoutOwner() async {
    const source = r'''
import 'package:better_effect/better_effect.dart';

Future<void> run(Module module) async {
  final runtime = await module.start();
  runtime.hashCode;
}
''';

    final offset = source.indexOf('module.start()');
    await assertDiagnostics(source, [lint(offset, 'module.start()'.length)]);
  }

  Future<void> test_reportsForkedRuntimeWithoutOwner() async {
    const source = r'''
import 'package:better_effect/better_effect.dart';

Future<void> run(Runtime runtime, Module module) async {
  final child = await runtime.fork(module);
  child.hashCode;
}
''';

    final offset = source.indexOf('runtime.fork(module)');
    await assertDiagnostics(source, [
      lint(offset, 'runtime.fork(module)'.length),
    ]);
  }

  Future<void> test_allowsTryFinallyOwnership() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

Future<void> run(Module module) async {
  final runtime = await module.start();
  try {
    runtime.hashCode;
  } finally {
    await runtime.close();
  }
}
''');
  }

  Future<void> test_allowsForkTryFinallyOwnership() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

Future<void> run(Runtime runtime, Module module) async {
  final child = await runtime.fork(module);
  try {
    child.hashCode;
  } finally {
    await child.close();
  }
}
''');
  }

  Future<void> test_allowsReturnedRuntime() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

Future<Runtime> build(Module module) async {
  return module.start();
}
''');
  }

  Future<void> test_allowsReturnedForkedRuntime() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

Future<Runtime> build(Runtime runtime, Module module) async {
  return runtime.fork(module);
}
''');
  }

  Future<void> test_allowsProviderOwnership() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:flutter/widgets.dart';

final class Child extends Widget {}

Future<Widget> build(Module module) async {
  final runtime = await module.start();
  return BetterEffectProvider(runtime: runtime, child: Child());
}
''');
  }

  Future<void> test_allowsTestTearDownOwnership() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

void addTearDown(Future<void> Function() callback) {}

Future<void> run(Module module) async {
  final runtime = await module.start();
  addTearDown(runtime.close);
}
''');
  }
}
