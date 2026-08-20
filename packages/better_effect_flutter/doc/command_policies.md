# Effect Command policies

`CommandPolicy` separates two decisions that used to be represented by one
fixed concurrency enum:

1. **trigger timing** — when an invocation becomes eligible to execute;
2. **execution coordination** — how that eligible invocation interacts with
   active or queued work.

The same `EffectCommand` and `EffectCommand0` types remain in use. Policies do
not create a stream runtime, a new Command hierarchy, or a new `Exit` variant.

## Basic policies

```dart
save = command(
  saveDraft,
  policy: const CommandPolicy.drop(),
);

search = commandWithInput(
  searchUsers,
  policy: const CommandPolicy.latest(cancelPrevious: true),
);

sync = commandWithInput(
  persistChange,
  policy: const CommandPolicy.queue(
    maxPending: 10,
    overflow: QueueOverflow.dropOldest,
  ),
);
```

`CommandPolicy.drop()` remains the default, so simple Command creation is still
concise.

## Compatibility with `EffectCommandConcurrency`

Existing code remains valid:

```dart
search = commandWithInput(
  searchUsers,
  concurrency: EffectCommandConcurrency.latest,
);
```

The compatibility values translate exactly:

| Compatibility value | Equivalent policy |
| --- | --- |
| `EffectCommandConcurrency.drop` | `CommandPolicy.drop()` |
| `EffectCommandConcurrency.latest` | `CommandPolicy.latest()` |
| `EffectCommandConcurrency.queue` | `CommandPolicy.queue()` |

Do not pass `policy` and `concurrency` together. New code should prefer the
policy model because it can express cancellation, trigger timing, queue bounds,
and overflow behavior without additional enum values.

## Caller outcomes

Policy-level replacement, rejection, and dropping are not domain failures. The
caller receives `ExitInterrupted<A, E>`:

```dart
final exit = await command.execute(input);

switch (exit) {
  case ExitInterrupted():
    // The invocation was replaced, rejected, dropped, cancelled, or disposed.
  case ExitFailure(:final error):
    // The accepted Effect produced a typed domain failure.
  case ExitDefect(:final defect):
    // The Effect or policy infrastructure raised an unexpected defect.
  case ExitSuccess(:final value):
    // The accepted invocation completed successfully.
}
```

No fake `E` value is invented for queue overflow or debounce replacement.
`EffectCommandPolicyEvent` carries the diagnostic reason when an application
needs to distinguish these decisions operationally.

## Drop

```dart
final policy = const CommandPolicy.drop();
```

While one authoritative execution is active, repeated invocations return that
same caller Future and do not start duplicate work. The repeated input is not
remembered by `retry()` because it was never accepted.

Use drop for submits, refresh actions, and destructive operations where a
second tap should coalesce with the active operation.

## Latest

```dart
final policy = const CommandPolicy.latest();
```

Every accepted invocation starts. Only the newest execution owns visible
Command state. Older callers still receive their own `Exit`, and stale physical
completion cannot overwrite the newest state.

To request cooperative interruption of the previous managed execution:

```dart
final policy = const CommandPolicy.latest(
  cancelPrevious: true,
);
```

The previous caller receives `ExitInterrupted` when interruption wins the
logical-result race. Its physical Future and resources remain Runtime-owned
until completion. This is switch-map-like ownership, not forceful cancellation
of arbitrary Dart Futures.

## Bounded queue

```dart
final policy = const CommandPolicy.queue(
  maxPending: 10,
  overflow: QueueOverflow.rejectNewest,
);
```

The active execution is not included in `maxPending`; it limits callers waiting
behind the active execution. Null means unbounded. Zero admits no waiting
callers.

Overflow choices:

| Overflow | Behavior |
| --- | --- |
| `rejectNewest` | Refuse the newest caller with `ExitInterrupted`. |
| `dropNewest` | Drop the newest caller with `ExitInterrupted`. |
| `dropOldest` | Interrupt the oldest queued caller and admit the newest. |

`rejectNewest` and `dropNewest` intentionally share the same caller outcome.
Their policy events differ so metrics can distinguish rejected capacity from a
deliberate dropping strategy.

Accepted queue inputs become `lastInputOrNull` immediately. Rejected or dropped
newest inputs do not replace the retry input. An input admitted after
`dropOldest` becomes the latest accepted retry input.

## Debounce

Debounce is available only for Commands with typed input:

```dart
search = commandWithInput(
  searchUsers,
  policy: const CommandPolicy.latest(
    trigger: TriggerPolicy.debounce(
      Duration(milliseconds: 300),
    ),
  ),
);
```

The default is trailing-only. Each newer input replaces the pending trailing
caller. Replaced callers receive `ExitInterrupted` and the quiet window restarts.
After the window closes, the latest input enters the execution policy.

Leading and trailing edges are explicit:

```dart
const TriggerPolicy.debounce(
  Duration(milliseconds: 300),
  leading: true,
  trailing: true,
)
```

With both enabled, the first input executes immediately and the latest input
received during the quiet window executes at the trailing edge. A leading-only
debounce executes the first input and suppresses later inputs until no calls
arrive for the configured duration.

## Throttle

```dart
search = commandWithInput(
  searchUsers,
  policy: const CommandPolicy.latest(
    trigger: TriggerPolicy.throttle(
      Duration(milliseconds: 500),
      leading: true,
      trailing: true,
    ),
  ),
);
```

The default throttle is leading-only. The first invocation starts immediately;
later invocations in the same window receive `ExitInterrupted`.

When trailing is enabled, only the latest pending input survives to the end of
the window. A trailing execution opens the next throttle window immediately, so
continuous input remains bounded to one execution per duration.

## Timing service

Debounce and throttle use the contextual core `EffectClock` service. Nothing is
installed implicitly:

```dart
final module = Module([
  .instance<EffectClock>(const SystemEffectClock()),
]);
```

A timed Command created without `EffectClock` returns an `ExitDefect` and
publishes `EffectCommandDefect`. Immediate policies do not resolve a clock.

Timers run as managed Runtime executions. Runtime shutdown, Command cancellation,
and Command disposal therefore reach the same cooperative `CancellationSignal`
used by ordinary Effects.

## Composing trigger and execution decisions

The trigger stage runs first. An eligible trailing invocation then enters drop,
latest, or queue normally:

```dart
final policy = const CommandPolicy.queue(
  maxPending: 3,
  overflow: QueueOverflow.dropOldest,
  trigger: TriggerPolicy.debounce(
    Duration(milliseconds: 250),
  ),
);
```

This debounces raw inputs, then serializes accepted operations. A trigger does
not bypass queue limits, latest state authority, or drop coalescing.

## Retry input

`retry()` is an ordinary policy invocation using the latest accepted input:

- drop does not remember a coalesced input;
- latest remembers every accepted input;
- queue remembers admitted inputs but not rejected newest inputs;
- debounce remembers the pending trailing input;
- throttle remembers leading or accepted trailing inputs, not suppressed calls.

Retry can itself be queued, debounced, throttled, coalesced, or rejected.

## Cancellation, reset, and disposal

`cancel(clearQueued: true)`:

- interrupts the authoritative execution;
- interrupts queued callers;
- interrupts a pending trailing caller;
- cancels the active debounce/throttle timer;
- publishes one visible interrupted state for the authoritative execution.

With `clearQueued: false`, queue callers remain and the next one starts after
active ownership is revoked. Trigger-delayed callers remain pending because the
caller explicitly requested queue preservation.

`reset()` returns false while an execution, queued caller, pending trailing
caller, or timing window exists. `dispose()` interrupts every managed execution,
timer, queued caller, and trigger-delayed caller exactly once.

## Policy observability

Observe decisions globally:

```dart
final commands = EffectCommands(
  runtime,
  policyObserver: (event) {
    logger.debug(
      'command.policy',
      metadata: {
        'label': event.debugLabel,
        'decision': event.decision.name,
        'reason': event.reason?.name,
        'invocationId': event.invocationId,
        'executionId': event.executionId,
        'pending': event.pendingCount,
        'queued': event.queuedCount,
      },
    );
  },
);
```

Or pass `policyObserver` to one Command. Inputs and Effect values are not
included in events. Observer failures are reported through Flutter's error
reporting and never change policy decisions or caller outcomes.

Providers, bootstrap widgets, and `runBetterEffectApp` also accept a shared
`policyObserver`.

## Deterministic tests

Use `ManualEffectClock` from the Flutter testing entrypoint:

```dart
import 'package:better_effect_flutter/testing.dart';

final clock = ManualEffectClock();
final runtime = await Module([
  .instance<EffectClock>(clock),
]).start();

final command = EffectCommands(runtime).withInput<String, Results, Failure>(
  search,
  policy: const CommandPolicy.latest(
    trigger: TriggerPolicy.debounce(Duration(milliseconds: 300)),
  ),
);

final result = command.execute('dart');
await clock.advance(const Duration(milliseconds: 300));
expect(await result, isExitSuccess<Results, Failure>());
```

`EffectCommandPolicyProbe` records policy decisions without adding a mocking
framework.
