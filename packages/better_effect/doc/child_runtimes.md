# Child Runtimes

`Runtime.fork` creates a feature-length environment between the application Runtime and a one-execution `runWith` overlay.

```dart
final feature = await appRuntime.fork(
  checkoutModule,
  label: 'checkout',
);

try {
  await feature.run(loadCheckout);
} finally {
  await feature.close();
}
```

## Resolution

Child bindings resolve before parent bindings. Missing services fall back to the parent Runtime, so child constructors and resources can depend on application services. Parent providers never resolve upward into a child environment.

An execution-scoped Module inside a child adds one more local layer:

```text
execution Module
      ↓
child Runtime
      ↓
parent Runtime
```

## Resource ownership

Resources declared by the child Module live until the child Runtime closes. They are shared across multiple child executions and are released exactly once.

Closing a child does not close its parent. Closing a parent coordinates its active child Runtimes first, using the same grace-period and interruption policy, before releasing parent resources.

Partial child startup follows normal Module acquisition semantics: already-acquired resources are released if a later provider fails to start.

## Shutdown and interruption

```dart
await feature.close(
  gracePeriod: const Duration(seconds: 2),
  interruptAfterGracePeriod: true,
);
```

A child waits for its own physical executions. Parent shutdown applies its configured close policy to children before parent cleanup, preserving the existing logical-versus-physical completion contract.

A Runtime that is closing or closed rejects new children.

## Observability

`RuntimeEventContext` exposes:

- `runtimeId` — identity of the Runtime that owns the event;
- `parentRuntimeId` — identity of the parent for child Runtimes;
- `runtimeLabel` — optional label supplied to `fork`.

Execution IDs remain local to each Runtime. Runtime identity makes application, feature, and execution boundaries independently correlatable without turning execution IDs into global IDs.

## Custom ResolverBackend implementations

Child environments use the same `ResolverBackendOverlayFactory` capability as execution-scoped Modules. An overlay must resolve local registrations first and fall back to the backend that created it.

Nested child/execution environments require overlays to expose the same capability recursively. `AutoInjectorBackend` supports this by default.

## Choosing the right lifetime

Use the application Runtime for application-wide services, `Runtime.fork` for resources shared by a feature across several executions, and `runWith`/`executeWith` for dependencies owned by one execution.
