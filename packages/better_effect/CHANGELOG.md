## Unreleased

- Added owned `Scope.make()` values with public child Scope, finalizer,
  acquisition, and close operations.
- Child Scopes now close before their parents in reverse creation order.
- Resource acquisition now registers cleanup atomically and immediately releases
  resources acquired after Scope closure begins.
- Resource release callbacks now receive the `Exit` that closed their Scope.
- Module resources and `EffectContext.acquire` now share the same Scope
  acquisition lifecycle.
- `Module.overrideWith` now replaces existing bindings in place and appends only
  new service identities, preserving resource startup and reverse cleanup order.
- Resource acquisition defects now identify the resource service and optional
  key while preserving the original dependency-resolution cause.

## 0.1.1

- Expanded the package documentation with complete installation, composition,
  runtime, resource, testing, and operational guidance.

## 0.1.0

- Initial core implementation.
- Added lazy `Effect<A, E>` values backed by `result_dart`.
- Added contextual service resolution with `use<T>()`.
- Added automatic typed failure propagation with `use.unwrap`, `use.result`, and `use.fail`.
- Added `Module`, `Binding`, and an `auto_injector` backend.
- Added factory, eager singleton, lazy singleton, instance, keyed, and resource bindings.
- Added runtime and execution scopes with reverse-order asynchronous cleanup.
- Added Effect locals, local service overrides, `Exit`, records-based `zip`, and core Effect operators.
