# Diagnostics

| Code | Layer | Default | Purpose |
|---|---|---:|---|
| `discarded_effect` | IDE/analyze | warning | Prevent a lazy Effect from being silently ignored. |
| `discarded_effect_execution` | IDE/analyze + graph CLI | warning | Prevent a managed execution handle and its Exit from being silently discarded. |
| `runtime_started_without_close` | IDE/analyze + graph CLI | warning | Detect a locally started Runtime without a statically visible lifecycle owner. |
| `unawaited_effect_context_operation` | IDE/analyze | warning | Preserve values and failure propagation from EffectContext operations. |
| `missing_binding_type_argument` | IDE/analyze | warning | Prevent constructor-backed Bindings from registering as `Object`. |
| `incompatible_provider` | IDE/analyze + graph | warning/error | Validate a Binding implementation against its service contract. |
| `duplicate_service_binding` | IDE/analyze + graph | warning/error | Prevent accidental duplicate service identities. |
| `effect_command_not_owned` | IDE/analyze + graph CLI | opt-in lint/info | Register Flutter Commands with a ViewModel owner so they are disposed. |
| `closed_runtime_exposed` | IDE/analyze + graph CLI | opt-in lint/info | Detect a local Runtime used after a visible close boundary. |
| `module_root_not_complete` | IDE/analyze + graph CLI | opt-in lint/info | Migrate visible application roots to `Module.complete`. |
| `repository_requests_repository` | IDE/analyze | opt-in lint | Keep cross-repository coordination in UseCases or ViewModels. |
| `viewmodel_requests_service` | IDE/analyze | opt-in lint | Keep ViewModels above low-level services. |
| `widget_requests_business_dependency` | IDE/analyze | opt-in lint | Keep Views dependent on ViewModels. |
| `singleton_viewmodel` | IDE/analyze | opt-in lint | Align ViewModel lifetime with its View or feature. |
| `missing_service` | graph CLI | error | Validate a complete or inferred root Module environment. Complete roots report dependency paths at the composition declaration. |
| `resource_dependency_declared_after_provider` | graph CLI | error | Detect direct or transitive resource dependencies that are acquired later during Module startup. |
| `dependency_cycle` | graph CLI | error | Detect dependency cycles. |
| `module_composition_cycle` | graph CLI | error | Detect recursive Module composition. |
| `module_not_found` | graph CLI | error | Report an explicit `--module` root that does not exist. |

The IDE rules operate on one resolved library at a time. The graph CLI indexes
the entire package because Module completeness and resource startup order are
cross-library properties. `Module.complete` lets an application identify roots
explicitly; inferred roots and `--module` remain available for existing projects.

Graph errors and lifecycle warnings are fatal in the CLI by default. Informational
migration findings remain visible without failing the command. Use
`--no-fatal-warnings` only during a staged rollout; it does not suppress or hide
the warning output.

See [Composition roots and lifecycle diagnostics](lifecycle_diagnostics.md) for
ownership patterns, CI usage, opt-in configuration, quick fixes, suppression,
and the static-analysis boundary.
