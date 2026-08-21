# better_effect_analyzer

[![pub package](https://img.shields.io/pub/v/better_effect_analyzer.svg)](https://pub.dev/packages/better_effect_analyzer)
[![Dart SDK](https://img.shields.io/badge/Dart-%E2%89%A53.10.0-0175C2.svg)](https://dart.dev/)

Static analysis and whole-project dependency-graph validation for
`better_effect` and `better_effect_flutter`.

This package has two complementary layers:

1. an official Dart Analysis Server plugin for fast diagnostics in the IDE,
   `dart analyze`, and `flutter analyze`;
2. a project-wide graph checker and CLI for validating complete `Module` roots
   across multiple Dart libraries.

The plugin catches local mistakes while you edit. The graph checker answers a
different question: whether the services requested throughout the project are
actually provided by the application Module, and whether those providers form a
valid dependency graph.

The analyzer package is tooling only. It is not a runtime dependency of
`better_effect` or `better_effect_flutter`.

## What it checks

The plugin registers five correctness warnings by default:

- discarded lazy Effects;
- ignored `EffectContext` operations;
- constructor-backed Bindings without an informative service type;
- incompatible Binding implementations;
- duplicate service identities declared directly in a Module.

It also registers four optional Flutter MVVM architecture lints:

- repositories requesting other repositories;
- ViewModels requesting low-level services;
- Widgets resolving business dependencies directly;
- ViewModels registered as application-lifetime singletons.

The graph CLI adds whole-project checks for:

- missing services in a root Module;
- dependency cycles;
- recursive Module composition;
- explicitly requested Modules that do not exist;
- duplicate or incompatible providers after Module composition;
- resources that require another resource declared later during startup.

## Requirements and compatibility

- Dart SDK 3.10 or newer;
- Flutter 3.38 or newer when analyzing a Flutter application;
- `better_effect` 0.4.x for the symbols being checked;
- analyzer 12.x tooling.

Version 0.4.0 continues to target the analyzer line used by Flutter SDKs that
pin `meta` to 1.18.0:

```yaml
dependencies:
  analysis_server_plugin: '>=0.3.14 <0.3.18'
  analyzer: ^12.1.0
```

The upper bound on `analysis_server_plugin` is deliberate: later plugin releases
move to newer analyzer lines and may conflict with a Flutter SDK's pinned
dependencies. Check your Flutter SDK's analyzer version before changing these
constraints.

## Installation

Install the package when you want to run the project-wide graph CLI:

```bash
dart pub add --dev better_effect_analyzer
```

Or add it manually:

```yaml
dev_dependencies:
  better_effect_analyzer: ^0.4.0
```

The Analysis Server plugin is configured from the project's top-level
`analysis_options.yaml`. It does not need to be imported by application code or
added as a runtime dependency.

## Enable the Analysis Server plugin

Add the plugin to the application's top-level `analysis_options.yaml`:

```yaml
include: package:flutter_lints/flutter.yaml

plugins:
  better_effect_analyzer:
    version: ^0.4.0
    diagnostics:
      repository_requests_repository: true
      viewmodel_requests_service: true
      widget_requests_business_dependency: true
      singleton_viewmodel: true
```

The five correctness warnings are enabled whenever the plugin is enabled. The
four architecture rules above are opt-in and can be turned on independently.

Restart the Dart Analysis Server after changing the `plugins` section. The
plugin applies to both Dart and Flutter projects:

```bash
dart analyze
flutter analyze
```

### Local monorepo development

When the analyzer package is checked out beside an application, use an absolute
path while developing the plugin:

```yaml
plugins:
  better_effect_analyzer:
    path: /absolute/path/to/workspace/packages/better_effect_analyzer
    diagnostics:
      repository_requests_repository: true
      viewmodel_requests_service: true
      widget_requests_business_dependency: true
      singleton_viewmodel: true
```

The plugin resolver expects the local path to be absolute. Published projects
should use `version` instead.

### Plugin-only versus CLI usage

Use only `analysis_options.yaml` when you want IDE and analyzer diagnostics.
Add `better_effect_analyzer` to `dev_dependencies` when you also want to run
`dart run better_effect_analyzer` from the application root:

```yaml
dev_dependencies:
  better_effect_analyzer: ^0.4.0
```

The analyzer package should not be added to `dependencies` and should never be
imported by production Flutter code.

## Local plugin diagnostics

### `discarded_effect`

Effects are lazy. Constructing an Effect as a standalone expression does not
execute it:

```dart
repository.save(user);
// Warning: the Effect is created but never executed.
```

Compose or run it explicitly:

```dart
await use.unwrap(repository.save(user));
return repository.save(user);
await runtime.run(repository.save(user));
```

### `unawaited_effect_context_operation`

`use.unwrap`, `use.result`, `use.tryAsync`, and `use.acquire` return Futures.
Ignoring one loses its value and its typed failure propagation:

```dart
use.unwrap(repository.save(user));
// Warning: await or return this operation.
```

Use `await` or return the operation from the current Effect body:

```dart
await use.unwrap(repository.save(user));
return use.unwrap(repository.save(user));
```

### `missing_binding_type_argument`

A constructor tear-off is typed as a `Function`. Without a service type,
Dart can infer `Object` and register the wrong contract:

```dart
Module([
  .provide(DatabaseLive.new),
  // Warning: add the service type argument.
]);
```

Declare the contract explicitly:

```dart
Module([
  .provide<Database>(DatabaseLive.new),
]);
```

A typed `ServiceKey` can also provide the inference constraint:

```dart
.provide(DatabaseLive.new, key: primaryDatabase)
```

### `incompatible_provider`

The implementation, instance, or resource acquired by a Binding must satisfy the
registered service contract:

```dart
Module([
  .provide<UserRepository>(AnalyticsService.new),
  // Warning: AnalyticsService is not a UserRepository.
]);
```

The rule understands regular method calls and Dart dot shorthand.

### `duplicate_service_binding`

A Module cannot contain two registrations with the same service type and key:

```dart
final module = Module([
  .provide<Database>(SqliteDatabase.new),
  .provide<Database>(MemoryDatabase.new),
  // Warning: duplicate unnamed Database binding.
]);
```

Different `ServiceKey` values are different identities:

```dart
Module([
  .provide<Database>(PrimaryDatabase.new, key: primaryDatabase),
  .provide<Database>(AnalyticsDatabase.new, key: analyticsDatabase),
]);
```

## Optional Flutter MVVM architecture lints

These rules are opt-in because teams use different boundaries. They implement
the architecture direction used by `better_effect_flutter`:

```text
Widget → ViewModel → Repository/UseCase → Service
```

### `repository_requests_repository`

Repositories should not coordinate other repositories directly:

```dart
final class BookingRepositoryLive implements BookingRepository {
  AppEffect<Booking> create() => Effect.result((use) async {
    final users = use<UserRepository>();
    // Warning: move cross-repository composition to a UseCase or ViewModel.
    return loadBooking(users);
  });
}
```

### `viewmodel_requests_service`

ViewModels should depend on repositories or use cases rather than low-level
infrastructure:

```dart
final class HomeViewModel extends EffectViewModel {
  AppEffect<HomeData> load() => Effect.result((use) async {
    final api = use<HomeApiClient>();
    // Warning: expose this operation through a Repository or UseCase.
    return api.loadHome();
  });
}
```

The rule recognizes common names such as `Service`, `Client`, `Api`,
`Database`, `DataSource`, and `Storage`, as well as conventional
`data/services`, `data/sources`, and `infrastructure` paths.

### `widget_requests_business_dependency`

Widgets should communicate with ViewModels instead of resolving repositories,
services, or use cases directly:

```dart
final class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final repository = context.readEffectService<UserRepository>();
    // Warning: expose the dependency through the ViewModel.
    return HomeBody(repository: repository);
  }
}
```

`readEffectService` remains valid in route and Provider factories. The lint
reports direct business reads inside Widget and State classes.

### `singleton_viewmodel`

ViewModels normally follow the lifecycle of their View or feature rather than
the entire application:

```dart
Module([
  .singleton<HomeViewModel>(HomeViewModel.new),
  // Warning: create this ViewModel at a View or feature boundary.
]);
```

The rule also recognizes the default lazy-singleton behavior of `provide`:

```dart
.provide<HomeViewModel>(HomeViewModel.new)

.provide<HomeViewModel>(
  HomeViewModel.new,
  lifetime: .singleton,
)
```

## Suppress or disable a plugin diagnostic

Use normal Dart suppression syntax for an isolated exception:

```dart
// ignore: better_effect_analyzer/discarded_effect
repository.save(user);
```

Or suppress a rule for a file:

```dart
// ignore_for_file: better_effect_analyzer/repository_requests_repository
```

For a project-wide architecture decision, leave the rule out of the
`diagnostics` map instead of suppressing every occurrence.

## Whole-project Module graph checking

A normal analyzer rule visits one resolved library at a time. The graph checker
builds an `AnalysisContextCollection` for the project and indexes classes,
service requests, constructor tear-offs, resource acquisition callbacks, and
Module declarations across the analyzed files.

By default it analyzes `lib`. Pass `--include-tests` to include `test` as well.
Generated files ending in these suffixes are skipped by default:

- `.g.dart`;
- `.freezed.dart`;
- `.mocks.dart`;
- `.gr.dart`;
- `.route.dart`.

### Run from the application root

If the CLI is in the application's dev dependencies:

```bash
dart run better_effect_analyzer
```

Pass an explicit project path when the current directory is not the application
root:

```bash
dart run better_effect_analyzer ../my_app
```

### Select root Modules

When no `--module` option is supplied, Modules not included by another Module
are treated as roots:

```bash
dart run better_effect_analyzer --module appModule
```

Repeat the option to validate more than one named root:

```bash
dart run better_effect_analyzer \
  --module appModule \
  --module backgroundModule
```

This is useful when a project intentionally has several independent
applications, isolates, or feature roots.

### Include tests

```bash
dart run better_effect_analyzer --include-tests
```

Use this when test-only Modules or fixtures should participate in graph
validation.

### Output formats and exit codes

Human-readable output is the default:

```bash
dart run better_effect_analyzer
# error   lib/config/app_module.dart:12:3 [missing_service] ...
```

Machine output is one diagnostic per line:

```bash
dart run better_effect_analyzer --format machine
# lib/config/app_module.dart:12:3:error:missing_service:...
```

JSON output is suitable for CI annotations or custom tooling:

```bash
dart run better_effect_analyzer --format json
```

The executable exits non-zero when it finds errors. The `--fatal-warnings` flag
is enabled by default; use `--no-fatal-warnings` when warnings should not fail
the command.

### Graph diagnostics

#### `missing_service`

The checker combines service requirements from:

- non-nullable constructor parameters used by AutoInjector;
- `use<T>()` and `EffectContext.service<T>()`;
- callable `services<T>()` and `services.get<T>()`;
- static `Effect.service<T>()`, including dot shorthand;
- `resource(acquire: ...)` callbacks;
- Module spreads, `Module.merge`, and `overrideWith`.

Example:

```text
error   lib/config/app_module.dart:12:3 [missing_service]
Provider 'UserRepository' requires 'Database', but Module 'appModule' doesn't provide it.
```

#### `resource_dependency_declared_after_provider`

This reports a direct or transitive startup dependency on a resource that is
declared later in the flattened Module. Move the dependency earlier or reorder
the owning resource so acquisition order matches the dependency graph.

#### `dependency_cycle`

The checker reports cycles across constructor and contextual dependencies:

```text
Database → SessionRepository → Database
```

#### `module_composition_cycle`

This reports recursive composition such as a Module that eventually includes
itself through `Module.merge`, spreads, or `overrideWith`.

#### `module_not_found`

This reports a name passed to `--module` when no matching Module declaration is
found in the analyzed project.

#### Provider diagnostics in the graph

The graph also reports `duplicate_service_binding` and
`incompatible_provider` after all included Modules and overrides are flattened.
The IDE versions of these rules remain useful for immediate local feedback.

### Static-analysis boundary

The checker follows statically visible declarations, list spreads, Module
composition, constructor tear-offs, and contextual requests. It cannot
reconstruct dependency lists assembled through reflection, runtime-generated
code, or complex dynamic control flow. Prefer declarative Modules when graph
validation is part of CI.

## Embed the graph checker

The public library exposes the graph model for custom tooling:

```dart
import 'package:better_effect_analyzer/better_effect_analyzer.dart';

final result = await BetterEffectGraphChecker('/path/to/app').check(
  options: const GraphCheckOptions(
    includeTests: true,
    moduleNames: {'appModule'},
  ),
);

for (final diagnostic in result.diagnostics) {
  print(diagnostic.toMachine());
}

if (result.hasErrors) {
  throw StateError('The better_effect graph is invalid.');
}
```

Available result helpers:

- `GraphDiagnostic.toJson` and `GraphCheckResult.toJson`;
- `GraphDiagnostic.toMachine`;
- `GraphCheckResult.hasErrors` and `hasWarnings`;
- sorted, immutable `diagnostics`.

Use `excludedSuffixes` in `GraphCheckOptions` when a generator uses additional
file suffixes:

```dart
const options = GraphCheckOptions(
  excludedSuffixes: {'.generated.dart', '.g.dart'},
);
```

## CI recipe

A Flutter project can run both layers:

```bash
flutter analyze --fatal-infos
dart run better_effect_analyzer --format machine
flutter test
```

A Dart-only project can replace the first and last commands with
`dart analyze --fatal-infos` and `dart test`.

## Development and API reference

From this package directory:

```bash
dart pub get
dart analyze --fatal-infos
dart test
dart run bin/better_effect_analyzer.dart --help
./tool/check.sh
```

- [API documentation](https://pub.dev/documentation/better_effect_analyzer/latest/)
- [Architecture notes](doc/architecture.md)
- [Diagnostic catalog](doc/diagnostics.md)
- [Changelog](CHANGELOG.md)
- [Source repository](https://github.com/nitoba/better-effect-dart)

The public import is:

```dart
import 'package:better_effect_analyzer/better_effect_analyzer.dart';
```
