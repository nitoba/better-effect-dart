## Unreleased

- Added the repository-level normative semantic contract and an independent
  cross-package conformance suite mapping stable lifecycle/outcome rules to
  executable rule IDs.
- Semantic compatibility changes now require the matching conformance scenario,
  affected package changelog entries, and a semantic migration ledger entry.
- Added `Runtime.fork` for feature-length child environments with local-first
  resolution and parent fallback.
- Child Module resources survive multiple executions, close exactly once with
  the child Runtime, and are coordinated before parent resources during parent
  shutdown.
- Runtime observer contexts now expose `runtimeId`, `parentRuntimeId`, and
  `runtimeLabel` so feature and execution boundaries can be correlated.
- Nested execution overlays preserve the complete parent fallback chain.
- Added typed-failure `Effect.retry` with `none`, fixed, linear, and
  exponential policies, optional full jitter, maximum delays, and
  explicit attempt-count semantics.
- Each retry attempt owns a child Scope that closes before policy
  evaluation or delay; cleanup defects retain Runtime precedence and
  prevent a broken typed-failure attempt from retrying.
- Added optional `EffectClock` and `EffectRandom` contracts with host,
  seeded, and manual test implementations; no service is installed
  implicitly.
- Added observable `RetryEvent` decisions, deterministic tests, package
  and website guides, and a retry benchmark.
- Added lazy `Effect.all` and `Effect.forEach` collection composition with
  sequential-by-default and positive bounded concurrency.
- Added explicit `Effect.allUnbounded` and `Effect.forEachUnbounded` APIs so
  unbounded fan-out cannot happen through an omitted limit.
- Collection results preserve input order and are returned as unmodifiable
  Lists, while scheduling remains FIFO.
- Typed failure selection is deterministic by lowest started input index; no new
  work starts after failure or interruption, and already-started operations
  remain physically owned until completion.
- Collection defects stay defects, worker resources retain normal Scope cleanup
  semantics, and sequential/bounded/unbounded benchmarks are included.

## 0.3.0

- Added `Runtime.executeWith`, `runWith`, and `runExitWith` for temporary
  execution-scoped Modules.
- Execution Modules resolve local providers first and fall back to the root
  Runtime without mutating root registrations.
- Local constructor injection can combine execution-local and root services,
  including typed `ServiceKey` registrations.
- Execution Module resources share the managed execution Scope and remain owned
  until physical completion after timeout or interruption.
- Partial local startup failures release previously acquired resources before
  publishing an execution defect.
- Added the optional `ResolverBackendOverlayFactory` capability for custom
  backends; `AutoInjectorBackend` supports isolated overlays by default.
- Added synchronous, SDK-neutral `RuntimeObserver` callbacks for execution,
  service resolution, resource acquisition/release, interruption, and cleanup
  failures.
- Runtime observer failures are isolated and can be reported through a
  best-effort `RuntimeObserverErrorHandler` without changing Effect outcomes.
- Execution events now expose labels, physical duration, opaque Scope identity,
  logical outcomes, and selected local metadata.
- Added `EffectLocal.metadata`, typed `EffectLocal.bind`, and `Effect.withLocals`
  for heterogeneous batch context composition.
- Added service resolution paths, execution-scoped Module event propagation,
  Flutter Command label verification, observer-ordering tests, and a standalone
  no-observer overhead benchmark.
- Added `package:better_effect/testing.dart` with `TestRuntime`, typed Exit
  matchers/extractors, deterministic gates and signals, ordered event recording,
  Runtime event waits, and active-execution leak assertions.
- Added a public `ResolverBackend` compatibility kit covering lifetimes, keys,
  constructor resolution, missing/circular dependencies, duplicate and
  post-commit registration, startup cleanup, close semantics, overlays, and
  optional native disposal probes.

## 0.2.0

- Added owned `Scope.make()` values with public child Scope, finalizer,
  acquisition, and close operations.
- Child Scopes now close before their parents in reverse creation order.
- Resource acquisition now registers cleanup atomically and immediately releases
  resources acquired after Scope closure begins.
- Resource release callbacks now receive the `Exit` that closed their Scope.
- Module resources and `EffectContext.acquire` now share the same Scope
  acquisition lifecycle.
- Added `Runtime.execute` and typed `EffectExecution<A, E>` handles with IDs,
  labels, logical exits, physical-running state, and cooperative interruption.
- `Runtime.run` and `runExit` now delegate to the managed execution path.
- Runtime shutdown now rejects new work, drains active executions, supports a
  grace period, and can request cooperative interruption before resource release.
- Timeouts keep their physical execution Scope owned until the source Future and
  all resource cleanup complete.
- Cleanup failures preserve typed failures and interruptions, aggregate with
  defects, and can be reported through a best-effort observer.
- Cancellation signals expose the first reason and a cooperative
  `throwIfCancelled` boundary.
- `Module.overrideWith` now replaces existing bindings in place and appends only
  new service identities, preserving resource startup and reverse cleanup order.
- Resource acquisition defects now identify the resource service and optional
  key while preserving the original dependency-resolution cause.
- Added a bounded, gate-driven regression suite for Scope races, timeout-owned
  resources, shutdown ordering, concurrent close, outcome authority, and cleanup
  precedence.

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
