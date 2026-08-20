## 0.3.0

- The graph checker now recognizes Modules passed directly to
  `Runtime.runWith`, `runExitWith`, and `executeWith` as execution overlays.
- Execution Modules may declare requirements supplied by the root Runtime while
  retaining duplicate, compatibility, cycle, and local resource-order checks.
- Added explicit `Module.complete` root discovery while retaining inferred roots
  and CLI `--module` selection for existing projects.
- Complete-root missing-service diagnostics now point to the composition root and
  include the dependency path that reaches the missing service.
- Added default lifecycle warnings for locally unowned Runtimes and discarded
  `EffectExecution` handles.
- Added opt-in lints for unowned Flutter Commands, local Runtime use after close,
  and visible application roots not yet marked with `Module.complete`.
- Added safe quick fixes for complete-root migration, observing or returning an
  execution Exit, local Runtime try/finally ownership, and local Command
  ownership.
- The graph CLI now emits the same lifecycle codes and messages as the IDE plugin,
  including standard local and file-level suppression support.
- Added the immutable, versioned `BetterEffectGraph` public model with stable
  Module, provider, service, dependency, diagnostic, root, lifetime, key, and
  source-location projections.
- Added graph export in text, JSON, DOT, and Mermaid, plus SARIF diagnostics for
  CI code-scanning integrations.
- Added `--explain`, `--why`, `--unused`, `--schema-version`, and file-output
  support to the graph CLI while preserving existing diagnostic output shapes.
- Added conservative complete-root reachability queries, deterministic renderers,
  embedded Dart APIs, schema negotiation, documentation, and CLI/API tests.

## 0.2.0

- Added `resource_dependency_declared_after_provider` to detect direct and
  transitive resource dependencies that are acquired too late during Module
  startup.
- Aligned graph override flattening with the core's stable in-place replacement
  semantics.

## 0.1.3

- Expanded the package documentation with plugin setup, diagnostics, graph
  validation, CLI, CI, and API usage guidance.

## 0.1.2

- Prepared the analyzer plugin and graph checker for independent pub.dev publication.
- Aligned the published compatibility documentation with the 0.1.2 release.

## 0.1.1

- Added the official Dart Analysis Server plugin entry point.
- Added default correctness warnings:
  - `discarded_effect`
  - `unawaited_effect_context_operation`
  - `missing_binding_type_argument`
  - `incompatible_provider`
  - `duplicate_service_binding`
- Added opt-in Flutter MVVM architecture lints:
  - `repository_requests_repository`
  - `viewmodel_requests_service`
  - `widget_requests_business_dependency`
  - `singleton_viewmodel`
- Added the project-wide Module graph checker and CLI with:
  - `missing_service`
  - `dependency_cycle`
  - `module_composition_cycle`
  - `module_not_found`
  - composed Module and override validation
  - human, machine, and JSON output
- Added resolved support for static `.service<T>()` dot shorthand requests.
