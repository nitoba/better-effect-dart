# Runtime observability

`RuntimeObserver` exposes SDK-neutral execution and resource events without making a logging, tracing, analytics, or error-reporting framework part of the core package.

```dart
final class LoggingObserver extends RuntimeObserver {
  @override
  void onExecutionEnd(ExecutionEndEvent event) {
    print(
      '${event.context.executionLabel ?? event.context.executionId} '
      'finished in ${event.duration}: ${event.outcome}',
    );
  }
}

final runtime = await appModule.start(
  observers: [LoggingObserver()],
  observerErrorHandler: (failure) {
    print(
      'Observer ${failure.observer.runtimeType} failed in '
      '${failure.callback}: ${failure.error}',
    );
  },
);
```

The same arguments are available on `Module.run` and `Module.runExit`.

## Why callbacks are synchronous

Observer callbacks are deliberately synchronous. This provides deterministic event ordering and prevents exporter Futures from becoming part of Effect completion, Scope cleanup, or Runtime shutdown.

An integration that writes asynchronously should enqueue an immutable event and return immediately:

```dart
final class QueueingObserver extends RuntimeObserver {
  QueueingObserver(this.queue);

  final EventQueue queue;

  @override
  void onServiceResolve(ServiceResolveEvent event) {
    queue.add(event);
  }
}
```

The Runtime catches every callback failure. It reports the failure to the optional `RuntimeObserverErrorHandler`, then continues with the next observer. The error handler is best-effort too: an exception raised by it is swallowed. Instrumentation cannot replace success, typed failure, defect, interruption, or cleanup outcomes.

## Event context

Every event contains an immutable `RuntimeEventContext`:

- `executionId`: zero for root Runtime activity; positive for managed Effects;
- `executionLabel`: the optional label supplied at the Runtime boundary;
- `parentExecutionId`: reserved for future structured child executions;
- `scopeId`: an opaque identity, never the mutable Scope object;
- `localMetadata`: selected Effect-local values visible at that boundary.

Events never expose a resolver, backend, Scope, resource instance, or mutable local map.

## Event ordering

For one managed execution, callbacks are emitted in registration order using this lifecycle:

```text
ExecutionStart
  ├── ServiceResolve*
  ├── ServiceAcquire*
  ├── Retry*                   // attempt decisions and planned delays
  ├── Interruption?            // first cancellation request only
  ├── ResourceRelease*         // reverse Scope ownership order
  ├── CleanupFailure?          // after failed releases are aggregated
  └── ExecutionEnd             // after physical work and Scope cleanup
```

Important details:

- `ExecutionStartEvent` is emitted exactly once before the Effect runner starts.
- `ExecutionEndEvent` is emitted exactly once after physical completion, including Scope cleanup.
- `ExecutionEndEvent.outcome` is the caller-visible logical outcome.
- A timeout or owner interruption may publish its logical outcome before physical completion; the end event waits for physical completion.
- `InterruptionSource.executionOwner` publishes `ExitInterrupted` immediately.
- `InterruptionSource.runtimeShutdown` only requests cooperative cancellation. The Effect may still return success if it does not cross a cancellation boundary.
- Resource release events are emitted before a cleanup-failure event.
- Cleanup-failure events do not change the existing cleanup-precedence policy.

Root Module resources use `executionId == 0`. Execution-scoped Module resources use the managed execution ID that owns the overlay.

## Named executions

All managed Runtime boundaries support labels:

```dart
final execution = runtime.execute(
  loadUser,
  label: 'users.load',
);

final exit = await runtime.runExit(
  loadUser,
  executionLabel: 'users.load',
);
```

`executeWith`, `runWith`, and `runExitWith` preserve the same label semantics. `better_effect_flutter` forwards an `EffectCommand.debugLabel` to `Runtime.execute` automatically.

## Typed local metadata

Normal `EffectLocal` values stay private to the Effect:

```dart
const authenticatedUser = EffectLocal<User?>(null, name: 'current-user');
```

Use `EffectLocal.metadata` only for values that should appear in observer events:

```dart
const requestId = EffectLocal<String>.metadata(
  'unknown-request',
  name: 'request.id',
);
const traceId = EffectLocal<String>.metadata(
  'unknown-trace',
  name: 'trace.id',
);
```

Apply heterogeneous locals in one type-safe batch:

```dart
final program = loadUser.withLocals([
  requestId.bind('req-123'),
  traceId.bind('trace-456'),
]);
```

`bind` validates the value against the local's generic type before it becomes an `EffectLocalBinding`. A batch can therefore contain different local types without using `dynamic` at the call site.

Metadata maps are immutable snapshots. The Runtime does not clone arbitrary values, so bind immutable diagnostic values such as strings, numbers, booleans, IDs, URIs, dates, or immutable records. Do not expose credentials, access tokens, personal data, or mutable application objects.

Nested local overrides are reflected at the event boundary where they are active. Execution start/end events use the statically visible top-level metadata bindings; service and resource events use the exact local context active for that operation.

## Service resolution paths

`ServiceResolveEvent` records:

- service type and logical `ServiceKey.name`;
- local-override or backend source;
- start time, completion time, and duration;
- success or the thrown resolution error;
- a human-readable resolution path.

Successful requests start with the requested service. For AutoInjector missing-service errors, the event retains the constructor or keyed resolution chain exposed by the backend, making failures such as `Controller -> Repository -> Database` inspectable without parsing logs in user code.

## Resources

`ServiceAcquireEvent` and `ResourceReleaseEvent` identify:

- the resource service type and optional logical key;
- root/execution ownership through `RuntimeEventContext`;
- whether acquisition came from a Module or `EffectContext.acquire`;
- duration and failure information;
- the `Exit` that closed the Scope during release.

The observer wraps the same atomic `Scope.acquire` path used by normal execution. Instrumentation does not introduce a second registration or cleanup mechanism.

## Retry decisions

`RetryEvent` identifies the one-based attempt, policy type, previous
typed failure, planned delay, and the decision that continued or stopped
the loop. `onRetry` uses the same execution ID, label, Scope identity,
and selected local metadata as the surrounding managed execution.

A cleanup failure still appears through `onCleanupFailure`; the retry
event then explains that the loop stopped with
`RetryDecision.cleanupFailed`. Observer failures remain isolated from
both policy decisions and Effect outcomes.

## Benchmarking the fast path

The package includes a standalone comparison between no observers and one no-op observer:

```bash
cd packages/better_effect
dart run benchmark/runtime_observer_benchmark.dart
```

The benchmark warms both Runtimes, executes the same service-resolving Effect repeatedly, and prints total time, nanoseconds per operation, and relative overhead. The no-observer path keeps the observer hub null, avoids timestamps and event allocation, and performs only a predictable null check at resolution/resource boundaries.

Benchmark numbers depend on SDK, CPU, build mode, and host load. Compare results on the same machine and SDK rather than treating one recorded value as a universal threshold.
