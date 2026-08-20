# Composition roots and lifecycle diagnostics

`better_effect_analyzer` can validate both the dependency graph and the ownership boundaries that keep a Runtime, managed execution, and Flutter Command alive for the right amount of time.

The diagnostics are intentionally conservative. The default warnings cover patterns that almost always discard ownership. More architecture-dependent checks are opt-in lints.

## Mark application roots explicitly

Use `Module.complete` for the Module that represents a runnable application environment:

```dart
final infrastructureModule = Module([
  .resource<Database>(
    acquire: (_) => Database.open(),
    release: (database, exit) => database.close(),
  ),
]);

final appModule = Module.complete([
  ...infrastructureModule,
  .provide<UserRepository>(UserRepositoryLive.new),
  .provide<LoadUser>(LoadUser.new),
]);
```

`Module.complete` behaves exactly like the normal constructor at runtime. The marker tells the graph checker that this Module must satisfy every dependency locally after composition and overrides.

When at least one complete root exists, the graph checker validates those roots instead of guessing from unreferenced Modules. Existing projects can keep using inferred roots or `--module` while migrating.

An incomplete marked root reports at the root declaration and includes a dependency path:

```text
Complete Module 'appModule' is incomplete.
Dependency path: LoadUser -> UserRepository -> Database reaches missing service 'Database'.
```

Several applications or entry points can mark independent roots in the same package.

## Default lifecycle warnings

### `runtime_started_without_close`

Reported when a Runtime is started inside a function and no lifecycle owner is statically visible:

```dart
Future<void> importData(Module module) async {
  final runtime = await module.start(); // warning
  await runtime.run(importEffect);
}
```

Prefer a one-shot Module boundary:

```dart
await module.run(importEffect);
```

Or close a long-lived local Runtime deterministically:

```dart
final runtime = await module.start();
try {
  await runtime.run(importEffect);
} finally {
  await runtime.close();
}
```

The rule recognizes returned/stored Runtimes, owned `BetterEffectProvider` boundaries, test teardown registration, and visible `try/finally` cleanup. Highly dynamic ownership helpers can be suppressed locally when necessary.

### `discarded_effect_execution`

Reported when `Runtime.execute` or `executeWith` creates an `EffectExecution` that is immediately discarded:

```dart
runtime.execute(loadUser); // warning
```

Keep the handle when interruption or physical ownership matters:

```dart
final execution = runtime.execute(loadUser);
```

Or observe the logical result:

```dart
final exit = await runtime.execute(loadUser).exit;
```

The IDE offers safe fixes to await or return `.exit` when the enclosing function shape permits it.

## Opt-in ownership lints

Enable architecture-dependent lifecycle checks explicitly:

```yaml
analyzer:
  plugins:
    - better_effect_analyzer

linter:
  rules:
    - effect_command_not_owned
    - closed_runtime_exposed
    - module_root_not_complete
```

### `effect_command_not_owned`

Warns when a Command is created directly inside an `EffectViewModel` or `EffectCommandOwner` without registering it for disposal.

Prefer the ViewModel helpers:

```dart
late final load = command(loadUsers);
```

Or register a directly created Command:

```dart
final load = ownCommand(commands(loadUsers));
```

The quick fix wraps a local creation with `ownCommand` only where invoking the instance owner is valid. It does not rewrite instance-field initializers when that transformation would be unsafe.

### `closed_runtime_exposed`

Flags a local Runtime used after a visible `close()` call in the same block:

```dart
await runtime.close();
runtime.execute(loadUser); // lint
```

Inspecting `isClosed` or `state` after closing is allowed. The rule deliberately stays within one local block and does not attempt whole-program alias analysis.

### `module_root_not_complete`

Helps migrate top-level Modules that are visibly used as application roots:

```dart
final appModule = Module([
  // ...
]);

Future<void> main() => runBetterEffectApp(
  module: appModule,
  app: const App(),
);
```

The quick fix changes the constructor to `Module.complete`. Reusable library Modules that are only composed into another Module are not reported.

## IDE and CLI consistency

The project-wide command reports the same lifecycle codes and messages as the IDE plugin:

```bash
dart run better_effect_analyzer
```

Graph errors remain errors. Default lifecycle ownership findings are warnings; conservative migration and architecture findings are informational in CLI output and opt-in lints in the IDE.

## Use in CI

The CLI returns a non-zero status for graph errors and, by default, lifecycle warnings:

```bash
dart run better_effect_analyzer --format=machine
```

This makes missing services, unowned local Runtimes, and discarded managed executions suitable release gates. Informational migration findings do not fail the command. During a staged adoption, warnings can remain visible without blocking the build:

```bash
dart run better_effect_analyzer --no-fatal-warnings
```

Prefer the machine or JSON formats when another tool collects annotations; the human format is intended for local review.

## Suppression

Prefer an explicit owner when the analyzer can understand it. For a dynamic framework integration, suppress the smallest possible scope:

```dart
// ignore: runtime_started_without_close
final runtime = await customHost.startRuntime(module);
```

The namespaced form is also accepted by the graph CLI:

```dart
// ignore: better_effect_analyzer/runtime_started_without_close
```

File-level suppression is supported:

```dart
// ignore_for_file: effect_command_not_owned
```

Suppressing a lifecycle diagnostic documents an ownership contract that static analysis cannot see. Add a short comment explaining which component closes or disposes the value.

## Static-analysis boundary

Lifecycle analysis does not model arbitrary reflection, dynamic invocation, container adapters, or aliases across an entire program. It focuses on high-confidence local patterns:

- local Runtime declarations and cleanup in the same function;
- managed execution expression statements;
- Command creation inside known owner types;
- local use after Runtime close;
- top-level Modules visibly passed to known application boundaries.

This boundary keeps the default rules useful without turning framework-specific architecture into mandatory policy.
