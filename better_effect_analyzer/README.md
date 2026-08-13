# better_effect_analyzer

Static analysis for `better_effect` and `better_effect_flutter`.

The package contains two complementary tools:

1. An official Dart Analysis Server plugin for immediate diagnostics in the IDE,
   `dart analyze`, and `flutter analyze`.
2. A whole-project Module graph checker for validations that need information
   from multiple libraries, such as missing services and dependency cycles.

There is intentionally a single analyzer package. Core Effect correctness and
optional Flutter MVVM architecture rules use the same resolved AST and the same
plugin configuration, while the runtime packages stay free of analyzer
dependencies.

## Compatibility

`better_effect_analyzer` 0.1.1 intentionally targets the analyzer line used by Flutter SDKs that pin `meta` to `1.18.0`:

```yaml
dependencies:
  analysis_server_plugin: 0.3.14
  analyzer: 12.1.0

dev_dependencies:
  analyzer_testing: 0.2.5
```

Do not widen `analysis_server_plugin` to `^0.3.14`: later 0.3.x releases move to analyzer 13/14 and can conflict with Flutter's SDK-pinned `meta` version.

For IDE-only usage, the plugin can be configured under the top-level `plugins:` section of `analysis_options.yaml`; it does not need to be a normal Flutter runtime dependency. Add it to `dev_dependencies` only when you also want to run the project-wide graph CLI with `dart run better_effect_analyzer`.


## Requirements

- Dart 3.10 or newer for this tooling package.
- A Flutter SDK that bundles Dart 3.10 or newer when used in a Flutter app.

The official plugin system starts in Dart 3.10 / Flutter 3.38. This release keeps
a Dart 3.10 lower bound because the official analyzer plugin system starts at
Dart 3.10. That tooling constraint does not change the lower bound of `better_effect` or
`better_effect_flutter`.

## Local workspace

A simple local layout is:

```text
workspace/
├── better_effect/
├── better_effect_flutter/
├── better_effect_analyzer/
└── my_app/
```

Enable the plugin in the **top-level** `analysis_options.yaml` of the app:

```yaml
include: package:flutter_lints/flutter.yaml

plugins:
  better_effect_analyzer:
    path: /absolute/path/to/workspace/better_effect_analyzer
    diagnostics:
      repository_requests_repository: true
      viewmodel_requests_service: true
      widget_requests_business_dependency: true
      singleton_viewmodel: true
```

Restart the Dart Analysis Server after changing the `plugins` section. The
current plugin resolver expects an absolute local path. Once the package is
published, the path can be replaced with a normal version constraint:

```yaml
plugins:
  better_effect_analyzer: ^0.1.1
```

The plugin is resolved directly from `analysis_options.yaml`; it does not need
to be added to the application's runtime dependencies. Add it as an optional
`dev_dependency` only when the graph CLI should be invokable from the app root:

```yaml
dev_dependencies:
  better_effect_analyzer:
    path: ../better_effect_analyzer
```

## Default correctness warnings

These warnings are enabled as soon as the plugin is enabled.

### `discarded_effect`

Effects are lazy. Creating one as an expression statement does not run it:

```dart
repository.save(user);
// ^ Effect created but never executed.
```

Use an explicit execution or composition boundary:

```dart
await use.unwrap(repository.save(user));
```

```dart
return repository.save(user);
```

```dart
await runtime.run(repository.save(user));
```

### `unawaited_effect_context_operation`

Operations such as `use.unwrap`, `use.result`, `use.tryAsync`, and
`use.acquire` return Futures. Ignoring them also ignores the value and the
intended failure propagation:

```dart
use.unwrap(repository.save(user));
//  ^ await or return this operation
```

```dart
await use.unwrap(repository.save(user));
```

### `missing_binding_type_argument`

Constructor-backed Bindings must identify the service they register. The
constructor parameter is intentionally typed as `Function`, so Dart cannot
infer `T` from a tear-off alone and otherwise falls back to `Object`:

```dart
Module([
  .provide(DatabaseLive.new),
  //       ^ add the service contract
]);
```

Use an explicit contract:

```dart
Module([
  .provide<Database>(DatabaseLive.new),
]);
```

The explicit type argument is optional when a typed `ServiceKey<T>` already
provides the inference constraint:

```dart
.provide(DatabaseLive.new, key: primaryDatabase)
```

### `incompatible_provider`

The constructor, instance, or resource registered by a Binding must satisfy the
service contract:

```dart
Module([
  .provide<UserRepository>(AnalyticsService.new),
  //                        ^ not a UserRepository
]);
```

The rule supports both regular invocations and Dart dot shorthands.

### `duplicate_service_binding`

A directly declared Module cannot accidentally register the same service
identity twice:

```dart
final appModule = Module([
  .provide<Database>(SqliteDatabase.new),
  .provide<Database>(MemoryDatabase.new),
  // ^ duplicate default Database binding
]);
```

Bindings using different `ServiceKey<T>` values remain distinct.

## Flutter MVVM architecture lints

These lints are opt-in because not every project adopts the same boundaries.
They implement the architecture direction used by `better_effect_flutter`:
Views observe ViewModels, ViewModels coordinate repositories or use cases, and
repositories access low-level services.

### `repository_requests_repository`

```dart
final class BookingRepositoryLive implements BookingRepository {
  AppEffect<Booking> create() => .result((use) async {
    final users = use<UserRepository>();
    //            ^ move cross-repository composition to a UseCase or ViewModel
    // ...
  });
}
```

### `viewmodel_requests_service`

```dart
final class HomeViewModel extends EffectViewModel {
  AppEffect<HomeData> load() => .result((use) async {
    final api = use<HomeApiClient>();
    //          ^ request a Repository or UseCase instead
    // ...
  });
}
```

The rule recognizes common low-level names such as `Service`, `Client`, `Api`,
`Database`, `DataSource`, and `Storage`, plus conventional infrastructure paths.

### `widget_requests_business_dependency`

```dart
final class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final repository = context.readEffectService<UserRepository>();
    //                         ^ expose this through the ViewModel
    // ...
  }
}
```

`readEffectService` remains valid at composition boundaries, such as route and
Provider factories. The rule only reports direct business dependency reads
inside Widget or State classes.

### `singleton_viewmodel`

```dart
Module([
  .singleton<HomeViewModel>(HomeViewModel.new),
  // ^ ViewModels should normally follow their View or feature lifecycle
]);
```

The rule also recognizes lazy application lifetime registrations, including the
default `.provide` lifetime:

```dart
.provide<HomeViewModel>(HomeViewModel.new)

.provide<HomeViewModel>(
  HomeViewModel.new,
  lifetime: .singleton,
)
```

## Whole-project Module graph

The IDE rules are intentionally local and fast. Module completeness is a
whole-project property: a provider can be declared in one file, request a
service through `use<T>()` in another, and be composed into an application
Module in a third file.

With the optional dev dependency configured, run the graph checker from the
app root:

```bash
dart run better_effect_analyzer
```

Without that dev dependency, run the executable from the analyzer package and
pass the application path:

```bash
cd ../better_effect_analyzer
dart run better_effect_analyzer ../my_app
```

Explicit project path:

```bash
dart run better_effect_analyzer ../my_app
```

Check named root Modules:

```bash
dart run better_effect_analyzer \
  --module appModule \
  --module backgroundModule
```

Include test Modules:

```bash
dart run better_effect_analyzer --include-tests
```

CI-friendly output:

```bash
dart run better_effect_analyzer --format machine
```

JSON output:

```bash
dart run better_effect_analyzer --format json
```

### `missing_service`

The checker combines:

- required constructor parameters used by AutoInjector;
- contextual callable requests through `use<T>()` and `Services<T>()`;
- method requests through `use.service<T>()` and `services.get<T>()`;
- static `Effect.service<T>()` requests, including `.service<T>()` dot shorthands;
- dependencies requested by `.resource(acquire: ...)`;
- Module composition with spreads and `Module.merge`;
- `Module.overrideWith`.

Example:

```text
error   lib/config/app_module.dart:12:3 [missing_service]
Provider 'UserRepository' requires 'Database', but Module 'appModule' doesn't provide it.
```

### `dependency_cycle`

```text
Database -> SessionRepository -> Database
```

The checker reports cycles across both constructor-injected and contextual
services.

### Other graph diagnostics

- `duplicate_service_binding`
- `incompatible_provider`
- `module_composition_cycle`
- `module_not_found`

## Root Module selection

When no `--module` option is supplied, reusable Modules included by another
Module are treated as partial environments. Modules that are not composed into
another Module are treated as roots.

Use repeated `--module` options when root selection must be explicit or when
Module composition contains dynamic runtime control flow.

## CI

A typical Flutter pipeline runs both analysis layers:

```bash
flutter analyze --fatal-infos
dart run ../better_effect_analyzer --format machine
flutter test
```

## Suppression

Plugin diagnostics use the normal Dart suppression syntax:

```dart
// ignore: better_effect_analyzer/discarded_effect
repository.save(user);
```

Or for a file:

```dart
// ignore_for_file: better_effect_analyzer/repository_requests_repository
```

Architecture rules should preferably be disabled in `analysis_options.yaml`
when a project deliberately follows different boundaries.

## Library API

The graph checker can also be embedded in tooling:

```dart
import 'package:better_effect_analyzer/better_effect_analyzer.dart';

final result = await BetterEffectGraphChecker(
  '/path/to/app',
).check(
  options: const GraphCheckOptions(
    moduleNames: {'appModule'},
  ),
);
```

## Development

```bash
dart pub get
./tool/check.sh
```

## Static-analysis boundary

The graph checker follows statically visible Module declarations, list spreads,
`Module.merge`, `overrideWith`, constructor tear-offs, and contextual service
requests. It cannot reconstruct arbitrary dependency lists assembled through
runtime reflection or complex dynamic control flow. Prefer declarative Modules
when compile-time graph validation matters.

## Flutter / analyzer compatibility

This release intentionally targets the analyzer 12.1 toolchain so it can coexist
with Flutter SDKs that pin `meta` to `1.18.0`.

```yaml
dependencies:
  analysis_server_plugin: 0.3.14
  analyzer: 12.1.0

dev_dependencies:
  analyzer_testing: 0.2.5
  test: 1.31.1
```

`NamedArgument` is an analyzer 13+ AST type. This package uses
`NamedExpression`, which is the corresponding API in analyzer 12.1.
