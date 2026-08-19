## Unreleased

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
