# Testing better_effect

Import the separate testing entrypoint from test code:

```dart
import 'package:better_effect/testing.dart';
import 'package:test/test.dart';
```

It re-exports the normal package API and adds test-owned Runtimes, deterministic
coordination primitives, Runtime event recording, Exit assertions, and the
`ResolverBackend` compatibility contract. Production code continues to import
`package:better_effect/better_effect.dart`.

## Normative lifecycle contract

This guide explains testing techniques; it does not redefine lifecycle or
outcome semantics. The versioned compatibility contract is
[`SEMANTICS.md`](../../../SEMANTICS.md), and its rule IDs are executed by the
independent `packages/better_effect_conformance` suite. A semantic rule change
must also update the affected changelog and
[`docs/semantic-migrations.md`](../../../docs/semantic-migrations.md).

## A test-owned Runtime

`TestRuntime` starts a real Runtime and attaches a
`RecordingRuntimeObserver`:

```dart
test('loads the configured clock', () async {
  final harness = await TestRuntime.start(
    testModule,
    registerCleanup: (cleanup) => addTearDown(cleanup),
  );

  final exit = await harness.runExit(
    readClock,
    executionLabel: 'clock.read',
  );

  expect(exit, isExitSuccess<String, AppFailure>('12:00'));
  harness.assertNoActiveExecutions();
});
```

The cleanup registrar keeps package code independent from `package:test`, while
still making ownership explicit at the test boundary. Without it, close the
harness in `finally`.

For a single scoped body, use `TestRuntime.use`:

```dart
final value = await TestRuntime.use<int>(testModule, (harness) async {
  final exit = await harness.runExit(loadValue);
  return expectExitSuccess(exit);
});
```

If both the body and cleanup fail, the original error and cleanup defect are
preserved in a `CompositeDefect`.

## Exit assertions

Matcher helpers work with ordinary `expect`:

```dart
expect(exit, isExitSuccess<User, UserFailure>());
expect(exit, isExitFailure<User, UserFailure>(isA<UserNotFound>()));
expect(exit, isExitDefect<User, UserFailure>(isA<StateError>()));
expect(exit, isExitInterrupted<User, UserFailure>());
```

Typed extractors return the payload or throw a descriptive expectation error:

```dart
final user = expectExitSuccess(exit);
final failure = expectExitFailure(exit);
final (:defect, :stackTrace) = expectExitDefect(exit);
expectExitInterrupted(exit);
```

This keeps a typed failure distinct from a defect or interruption in tests.

## Coordinate asynchronous work without sleeps

Use `TestGate<T>` when the code under test waits for a value:

```dart
final gate = TestGate<Response>();

final execution = harness.execute(
  Effect.result((_) => gate.future),
);

// Assert the running state here.
gate.complete(response);
expect(await execution.exit, isExitSuccess<Response, AppFailure>());
```

Use `TestSignal` for a release-only boundary:

```dart
final started = TestSignal();
final continueWork = TestSignal();

final execution = harness.execute(
  Effect.result((_) async {
    started.signal();
    await continueWork.wait;
    return unit;
  }),
);

await started.wait;
continueWork.signal();
```

`TestEventRecorder<T>` records exact acquisition, use, and cleanup order:

```dart
final events = TestEventRecorder<String>();

events.record('acquire:database');
events.record('release:database');

events.expectEvents([
  'acquire:database',
  'release:database',
]);
```

These primitives make concurrency deterministic without wall-clock sleeps.

## Advance retry time manually

`ManualEffectClock` completes sleeps only when the test advances time:

```dart
final clock = ManualEffectClock();
final harness = await TestRuntime.start(
  Module([.instance<EffectClock>(clock)]),
  registerCleanup: (cleanup) => addTearDown(cleanup),
);

final scheduled = harness.observer.next<RetryEvent>(
  where: (event) => event.decision == RetryDecision.retryScheduled,
);
final execution = harness.execute(request.retry(policy));

expect((await scheduled).plannedDelay, const Duration(seconds: 1));
await clock.advance(const Duration(seconds: 1));
```

This verifies retry without wall-clock sleeps. Owner interruption also
removes a pending manual sleep, so cancellation tests stay deterministic.

## Runtime events and leak assertions

The attached observer exposes immutable event snapshots and typed waits:

```dart
final ended = harness.observer.next<ExecutionEndEvent>(
  where: (event) => event.context.executionLabel == 'users.load',
);

await harness.runExit(loadUsers, executionLabel: 'users.load');
expect((await ended).outcome, isA<ExitSuccess>());
```

`activeExecutionIds` contains executions that started but have not reached
physical completion. Call `harness.assertNoActiveExecutions()` after releasing
all gates to catch tests that only observed a logical timeout or interruption
while physical work was still running.

Observer callback failures are available as an immutable
`harness.observerErrors` snapshot. They retain the Runtime's normal best-effort
observability semantics.

## Verify a custom ResolverBackend

Backend authors can run the public compatibility contract inside one ordinary
test:

```dart
test('MyBackend follows the better_effect contract', () async {
  await runResolverBackendContractTests(
    createBackend: MyBackend.new,
  );
});
```

The contract creates a fresh backend per scenario and verifies:

- factory, eager singleton, lazy singleton, and instance semantics;
- keyed and unkeyed isolation;
- constructor injection;
- missing and circular dependency failure;
- duplicate registration rejection;
- idempotent `commit`, `activate`, and `close`;
- constructor registration rejection after commit;
- resource-style instance registration after commit;
- constructor defect preservation;
- partial Runtime startup cleanup;
- post-close resolution failure;
- execution-overlay isolation when supported.

The report identifies every scenario by name:

```dart
final report = await inspectResolverBackendContract(
  createBackend: MyBackend.new,
);

for (final failure in report.failures) {
  print('${failure.scenario.name}: ${failure.error}');
}
```

### Native disposal callbacks

`ResolverBackend` does not prescribe how a container registers native disposal
callbacks. Backends that expose such a mechanism can provide an optional
`ResolverBackendDisposalProbeFactory`:

```dart
await runResolverBackendContractTests(
  createBackend: MyBackend.new,
  createDisposalProbe: createMyBackendDisposalProbe,
);
```

Without a probe, only that capability is reported as skipped. Required contract
failures still fail the report. `AutoInjectorBackend` is verified against every
scenario, including disposal and execution overlays.

## Test doubles

The toolkit does not include a mocking framework. Prefer small fakes and Module
overrides:

```dart
final module = productionModule.overrideWith([
  .instance<Clock>(FakeClock.fixed(now)),
  .instance<UserRepository>(FakeUserRepository(users)),
]);
```

This executes the same Effect and Runtime lifecycle used in production while
replacing only the I/O boundary.
