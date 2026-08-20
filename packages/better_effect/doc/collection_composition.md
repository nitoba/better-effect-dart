# Collection composition

`Effect.all` and `Effect.forEach` compose homogeneous collections without
introducing a scheduler, queue abstraction, or fiber runtime.

```dart
final users = Effect.forEach(
  userIds,
  loadUser,
  concurrency: 4,
);
```

The returned Effect is lazy. The input Iterable is not traversed and the mapper
is not called until a Runtime executes it.

## Choose concurrency deliberately

Bounded collection APIs are sequential by default:

```dart
final sequential = Effect.forEach(
  userIds,
  loadUser,
); // concurrency: 1
```

Set a positive finite worker limit when operations are independent:

```dart
final bounded = Effect.forEach(
  userIds,
  loadUser,
  concurrency: 4,
);
```

Unbounded execution is a separate API so an omitted limit cannot accidentally
start an arbitrary number of operations:

```dart
final unbounded = Effect.forEachUnbounded(
  userIds,
  loadUser,
);
```

The same choices are available for an existing collection of Effects:

```dart
final sequential = Effect.all([
  loadProfile(),
  loadNotifications(),
  loadPreferences(),
]);

final bounded = Effect.all(
  requests,
  concurrency: 8,
);

final unbounded = Effect.allUnbounded(requests);
```

`concurrency` must be greater than zero. Sequential execution is expressed with
`concurrency: 1`; there is no magic integer for unbounded execution.

## Ordering and scheduling

Items are claimed in FIFO input order. Completion order does not affect the
returned List:

```dart
final values = await module.run(
  Effect.forEach(
    inputs,
    runOperation,
    concurrency: 3,
  ),
);
```

On success, the output order matches `inputs`, even when later operations finish
first. The List is unmodifiable. Empty input succeeds with an empty
unmodifiable List.

No more than the configured number of item Effects are physically active at
once. `forEachUnbounded` intentionally uses the input length as the worker
count.

## Typed failure selection

After a worker observes a typed failure:

1. no new input is claimed;
2. Effects already started continue to physical completion;
3. resources remain owned by the enclosing execution Scope;
4. when several started items fail, the failure with the lowest input index is
   returned.

The input-index rule is deterministic and does not depend on Future completion
order.

```text
started: 0, 1, 2
completion: 2 fails, 1 succeeds, 0 fails
result: failure from input 0
```

An item that was never started cannot become the authoritative failure.

## Defects and interruption

Defects remain defects. If several started items defect, the lowest input index
selects the propagated defect. A defect is never converted into the collection's
typed error.

Traversing the input Iterable and invoking the `forEach` mapper are also part of
the lazy execution boundary. If either operation throws, the thrown object is a
defect unless application code deliberately maps it before collection
composition.

When no caller-visible outcome has already been published, completion uses:

```text
lowest-index started defect
  > cancellation observed at the collection boundary
  > lowest-index started typed failure
  > successful ordered values
```

`EffectExecution.interrupt()` is a first-outcome boundary: it publishes
`ExitInterrupted` immediately. A defect that appears later while a started
worker drains does not replace that logical result; the Runtime retains it as a
deferred physical failure and can surface it during `Runtime.close()`.

Every worker receives the same `CancellationSignal` as the enclosing execution.
Once interruption is observed, no new items start. Already-started Dart Futures
are not forcefully cancelled; the Runtime keeps their Scope owned until they
finish.

This distinction matters when a caller has already received
`ExitInterrupted`:

```dart
final execution = runtime.execute(batch);
execution.interrupt(reason: 'screen-disposed');

final exit = await execution.exit; // logical interruption
// execution.isRunning may remain true until started workers finish.
```

Runtime shutdown follows the same physical-ownership rule.

## Resources inside workers

All item Effects run in the enclosing execution Scope:

```dart
final exports = Effect.forEach(
  ids,
  (id) => Effect<Export, ExportFailure>.result((use) async {
    final file = await use.acquire(
      openTemporaryFile(id),
      release: (file, exit) => file.delete(),
    );

    return createExport(file);
  }),
  concurrency: 4,
);
```

A resource acquired by a started worker remains valid until the collection
execution closes. It is released even when another worker fails, defects, times
out, or the owner interrupts the execution.

Collection composition does not create an attempt Scope per item. Retry attempt
Scopes are a separate policy concern.

## Timeout

A timeout can publish a typed failure before the batch physically completes:

```dart
final timed = batch.timeout(
  const Duration(seconds: 5),
  onTimeout: BatchTimedOut.new,
);
```

Dart Futures are not generally cancellable. The Runtime therefore keeps every
started worker and resource owned until physical completion. Use a cancellable
adapter or observe `use.cancellation` inside item Effects when the underlying API
supports cooperative cancellation.

## Testing

Use deterministic gates instead of sleeps:

```dart
final gate = TestGate<User>();
final started = TestSignal();

final batch = Effect.forEach(
  userIds,
  (id) => Effect<User, UserFailure>.result((_) async {
    started.signal();
    return gate.future;
  }),
  concurrency: 1,
);
```

The public testing entrypoint also provides `TestRuntime`, Runtime event waits,
resource-order recording, and active-execution leak assertions.

## Benchmark

A standalone comparison is included:

```bash
dart run benchmark/effect_collection_benchmark.dart
```

It measures sequential, bounded, and explicit unbounded traversal in the same
Runtime. Treat the output as a local comparison rather than a universal
performance threshold.
