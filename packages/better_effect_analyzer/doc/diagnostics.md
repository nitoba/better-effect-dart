# Diagnostics

| Code | Layer | Default | Purpose |
|---|---|---:|---|
| `discarded_effect` | IDE/analyze | warning | Prevent a lazy Effect from being silently ignored. |
| `unawaited_effect_context_operation` | IDE/analyze | warning | Preserve values and failure propagation from EffectContext operations. |
| `missing_binding_type_argument` | IDE/analyze | warning | Prevent constructor-backed Bindings from registering as `Object`. |
| `incompatible_provider` | IDE/analyze + graph | warning/error | Validate a Binding implementation against its service contract. |
| `duplicate_service_binding` | IDE/analyze + graph | warning/error | Prevent accidental duplicate service identities. |
| `repository_requests_repository` | IDE/analyze | opt-in lint | Keep cross-repository coordination in UseCases or ViewModels. |
| `viewmodel_requests_service` | IDE/analyze | opt-in lint | Keep ViewModels above low-level services. |
| `widget_requests_business_dependency` | IDE/analyze | opt-in lint | Keep Views dependent on ViewModels. |
| `singleton_viewmodel` | IDE/analyze | opt-in lint | Align ViewModel lifetime with its View or feature. |
| `missing_service` | graph CLI | error | Validate the complete root Module environment. |
| `resource_dependency_declared_after_provider` | graph CLI | error | Detect direct or transitive resource dependencies that are acquired later during Module startup. |
| `dependency_cycle` | graph CLI | error | Detect dependency cycles. |
| `module_composition_cycle` | graph CLI | error | Detect recursive Module composition. |
| `module_not_found` | graph CLI | error | Report an explicit `--module` root that does not exist. |

The IDE rules operate on one resolved library at a time. The graph CLI indexes
the entire package because Module completeness and resource startup order are
cross-library properties.
