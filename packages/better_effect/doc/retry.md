# Retry policies

`Effect.retry` re-executes a lazy Effect after eligible typed failures. It does
not retry defects, successful values, or interrupted executions.

```dart
final request = loadRemoteData().retry(
  RetryPolicy.exponential(
    maxAttempts: 4,
    initialDelay: const Duration(milliseconds: 200),
    maxDelay: const Duration(seconds: 3),
  ),
  whileError: (error) => error is TemporaryNetworkFailure,
);
```

`maxAttempts` includes the initial execution. In this example the Effect can run
at most four times, not five.

## Install timing services explicitly

Delayed retry uses an [EffectClock]. Jitter uses an [EffectRandom]. Neither
service is installed implicitly:

```dart
final module = Module([
  .instance<EffectClock>(const SystemEffectClock()),
  .instance<EffectRandom>(SystemEffectRandom()),
  .provide<RemoteRepository>(RemoteRepositoryLive.new),
]);
```

A zero-delay retry does not resolve `EffectClock`. A policy without jitter does
not resolve `EffectRandom`. This keeps applications that do not use timing or
randomness unchanged.

The contracts are deliberately small:

```dart
abstract interface class EffectClock {
  DateTime now();
  Future<void> sleep(
    Duration duration,
    CancellationSignal cancellation,
  );
}

abstract interface class EffectRandom {
  double nextDouble();
}
```

Applications can replace them through ordinary Module overrides. There is no
global clock, random source, scheduler, or background worker.

## Built-in policies

### No retry

```dart
final once = operation.retry(RetryPolicy.none());
```

### Fixed

```dart
final fixed = operation.retry(
  RetryPolicy.fixed(
    maxAttempts: 3,
    delay: const Duration(milliseconds: 250),
  ),
);
```

### Linear

The first failed attempt waits `initialDelay`. Each later failure adds
`increment`. When `increment` is omitted, `initialDelay` is used.

```dart
final linear = operation.retry(
  RetryPolicy.linear(
    maxAttempts: 5,
    initialDelay: const Duration(milliseconds: 100),
    increment: const Duration(milliseconds: 200),
    maxDelay: const Duration(seconds: 1),
  ),
);
```

The uncapped sequence above is `100 ms`, `300 ms`, `500 ms`, `700 ms`; the
maximum delay caps later values.

### Exponential

```dart
final exponential = operation.retry(
  RetryPolicy.exponential(
    maxAttempts: 5,
    initialDelay: const Duration(milliseconds: 100),
    factor: 2,
    maxDelay: const Duration(seconds: 2),
  ),
);
```

The sequence begins `100 ms`, `200 ms`, `400 ms`, `800 ms`.

Built-in policies validate attempt counts, negative durations, invalid factors,
and delay overflow. Supply `maxDelay` when a long exponential schedule must be
capped rather than rejected.

## Full jitter

Set `jitter: true` to choose a uniform delay from zero up to the calculated
value:

```dart
final resilient = operation.retry(
  RetryPolicy.exponential(
    maxAttempts: 5,
    initialDelay: const Duration(milliseconds: 200),
    maxDelay: const Duration(seconds: 5),
    jitter: true,
  ),
);
```

Jitter calls `EffectRandom.nextDouble()` only when the calculated delay is
positive. The returned value must be finite and in `[0, 1)`.

Use `SeededEffectRandom` when a reproducible pseudo-random sequence is useful:

```dart
final testModule = productionModule.overrideWith([
  .instance<EffectRandom>(SeededEffectRandom(42)),
]);
```

## Filter typed failures

`whileError` restricts which typed failures may retry without changing the error
type:

```dart
final result = fetchUser().retry(
  RetryPolicy.fixed(
    maxAttempts: 3,
    delay: const Duration(milliseconds: 200),
  ),
  whileError: (failure) => switch (failure) {
    NetworkUnavailable() => true,
    _ => false,
  },
);
```

A rejected failure is returned immediately. If the predicate throws, the thrown
object is a defect.

## One Scope per attempt

Each attempt receives a child Scope of the managed execution:

```dart
final effect = Effect<Response, RequestFailure>.result((use) async {
  final transaction = await use.acquire(
    beginTransaction(),
    release: (transaction, exit) => transaction.close(exit),
  );

  return sendRequest(transaction);
}).retry(policy);
```

The attempt Scope closes before policy evaluation, delay, or the next attempt.
Therefore attempt-local resources never overlap accidentally across retries.
Runtime-owned Module resources remain shared across every attempt.

Cleanup keeps the existing outcome precedence:

- cleanup after success turns that attempt into a defect;
- cleanup after a defect is combined through `CompositeDefect`;
- cleanup after typed failure or interruption preserves the primary outcome and
  emits `CleanupFailureDiagnostic`;
- a typed failure whose attempt cleanup failed is not retried.

That final rule prevents a broken release from being silently treated as an
ordinary retryable domain failure.

## Interruption

Every attempt and delay observes the managed execution's
`CancellationSignal`:

```dart
final execution = runtime.execute(
  request.retry(policy),
  label: 'remote.request',
);

execution.interrupt(reason: 'screen-disposed');
final exit = await execution.exit;
```

Owner interruption publishes `ExitInterrupted` immediately. Physical work can
remain owned while a non-cancellable Future or attempt cleanup finishes. No new
attempt starts after cancellation is observed.

`SystemEffectClock.sleep` races its timer against the cancellation signal.
Custom clocks must preserve the same cooperative contract.

## Observability

`RuntimeObserver.onRetry` receives a `RetryEvent` for policy decisions and
terminal attempt outcomes:

```dart
final class AppObserver extends RuntimeObserver {
  @override
  void onRetry(RetryEvent event) {
    logger.info('retry', {
      'execution.id': event.context.executionId,
      'execution.label': event.context.executionLabel,
      'attempt': event.attempt,
      'decision': event.decision.name,
      'delay.ms': event.plannedDelay?.inMilliseconds,
    });
  }
}
```

`RetryDecision` distinguishes:

- `retryScheduled`;
- `succeeded`;
- `policyStopped`;
- `failureRejected`;
- `interrupted`;
- `defect`;
- `cleanupFailed`.

Observer callbacks remain synchronous, best-effort instrumentation. Throwing
from an observer does not change retry decisions or Effect outcomes.

## Custom policies

Implement `RetryPolicy<E>` when the built-ins are insufficient:

```dart
final class TwoAttemptPolicy implements RetryPolicy<AppFailure> {
  const TwoAttemptPolicy();

  @override
  Duration? nextDelay(RetryContext<AppFailure> context) {
    return context.attempt < 2 ? Duration.zero : null;
  }
}
```

`RetryContext.attempt` is one-based and identifies the attempt that just failed.
`RetryContext.error` contains that typed failure. Custom jitter can call
`context.nextRandom()`; doing so lazily resolves `EffectRandom`.

A custom policy must return null or a non-negative Duration. Invalid values and
exceptions remain defects.

## Deterministic tests

Import the testing entrypoint and install `ManualEffectClock`:

```dart
import 'package:better_effect/testing.dart';

final clock = ManualEffectClock();
final harness = await TestRuntime.start(
  Module([
    .instance<EffectClock>(clock),
  ]),
  registerCleanup: (cleanup) => addTearDown(cleanup),
);

final scheduled = harness.observer.next<RetryEvent>(
  where: (event) => event.decision == RetryDecision.retryScheduled,
);
final execution = harness.execute(request.retry(policy));

final event = await scheduled;
expect(event.plannedDelay, const Duration(seconds: 1));

await clock.advance(const Duration(seconds: 1));
expect(await execution.exit, isExitSuccess<Response, RequestFailure>());
```

`ManualEffectClock` never waits for wall time. Pending sleeps complete only when
the test advances its clock, while interruption removes a pending sleep
immediately.

## Benchmark

A standalone benchmark compares successful execution, one zero-delay retry, and
five attempts:

```bash
dart run benchmark/effect_retry_benchmark.dart
```

Use it as a local comparison. It is not a universal timing threshold.
