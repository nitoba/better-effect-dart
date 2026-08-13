# Diagnostics

| Code | Layer | Default | Purpose |
|---|---|---:|---|
| `discarded_effect` | IDE/analyze | warning | Prevent a lazy Effect from being silently ignored. |
| `unawaited_effect_context_operation` | IDE/analyze | warning | Preserve values and failure propagation from `use.unwrap`, `use.result`, `use.tryAsync`, and `use.acquire`. |
| `missing_binding_type_argument` | IDE/analyze | warning | Prevent constructor-backed Bindings from silently registering as `Object`. |
| `incompatible_provider` | IDE/analyze + graph | warning/error | Validate a Binding implementation against its service contract. |
| `duplicate_service_binding` | IDE/analyze + graph | warning/error | Prevent accidental duplicate service identities. |
| `repository_requests_repository` | IDE/analyze | opt-in lint | Keep cross-repository coordination in UseCases or ViewModels. |
| `viewmodel_requests_service` | IDE/analyze | opt-in lint | Keep ViewModels above low-level data and platform services. |
| `widget_requests_business_dependency` | IDE/analyze | opt-in lint | Keep Views dependent on ViewModels rather than business infrastructure. |
| `singleton_viewmodel` | IDE/analyze | opt-in lint | Align ViewModel lifetime with its View or feature. |
| `missing_service` | graph CLI | error | Validate the complete root Module environment. |
| `dependency_cycle` | graph CLI | error | Detect cycles across constructor and contextual dependencies. |
| `module_composition_cycle` | graph CLI | error | Detect recursive Module composition. |
| `module_not_found` | graph CLI | error | Report an explicit `--module` root that does not exist. |

The IDE rules operate on one resolved library at a time. The graph CLI indexes
the entire package because Module completeness is a cross-library property.

## `module_not_found`

A requested Module root could not be found.
