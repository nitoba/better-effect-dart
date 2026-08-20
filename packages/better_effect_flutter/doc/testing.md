# Testing better_effect_flutter

Import the Flutter testing entrypoint:

```dart
import 'package:better_effect_flutter/testing.dart';
import 'package:flutter_test/flutter_test.dart';
```

It re-exports every core test helper and adds Command probes, typed state
assertions, one-shot listener verification, and a minimal widget boundary.

## Observe visible Command states

`EffectCommandProbe` listens to the same `ValueListenable` used by the UI:

```dart
final probe = EffectCommandProbe<User, UserFailure>(viewModel.loadUser);
addTearDown(probe.dispose);

final running = probe.waitFor<
  EffectCommandRunning<User, UserFailure>
>();
final success = probe.waitFor<
  EffectCommandSuccess<User, UserFailure>
>();

final exit = await viewModel.loadUser.execute(userId);

expect(await running, isA<EffectCommandRunning<User, UserFailure>>());
expect((await success).value.id, userId);
expect(exit, isExitSuccess<User, UserFailure>());
```

The probe records revisions in order. `waitFor<S>` accepts the current or a
future state; `nextWhere` waits only for a later revision. Every wait has a
bounded default timeout.

For a compact lifecycle assertion:

```dart
probe.expectStateTypes([
  EffectCommandIdle<User, UserFailure>,
  EffectCommandRunning<User, UserFailure>,
  EffectCommandSuccess<User, UserFailure>,
]);
```

## Typed state extractors

When the current state matters more than its history, use the framework-neutral
extractors:

```dart
final user = expectCommandSuccess(command.value);
final failure = expectCommandFailure(command.value);
final (:defect, :stackTrace) = expectCommandDefect(command.value);

expectCommandIdle(command.value);
expectCommandRunning(command.value);
expectCommandInterrupted(command.value);
```

A wrong state raises `EffectCommandTestExpectationException` with the expected
and actual state types.

## Test one-shot listener delivery

`EffectCommandListenerProbe` is passed to `onChanged`:

```dart
final listener = EffectCommandListenerProbe<User, UserFailure>();

await tester.pumpWidget(
  EffectCommandListener<User, UserFailure>(
    command: command,
    onChanged: listener.call,
    child: const UserScreen(),
  ),
);
```

After the interaction:

```dart
expect(
  listener.deliveriesOf<EffectCommandFailure<User, UserFailure>>(),
  hasLength(1),
);
listener.expectUniqueRevisions();
```

This verifies that a visible revision was not delivered twice to navigation,
SnackBar, dialog, or analytics code.

## Pump an externally owned Runtime

`BetterEffectTestApp` wraps `BetterEffectProvider.value` and adds
`Directionality`:

```dart
final harness = await TestRuntime.start(
  testModule,
  registerCleanup: (cleanup) => addTearDown(cleanup),
);

await tester.pumpWidget(
  BetterEffectTestApp(
    runtime: harness.runtime,
    child: const UserScreen(),
  ),
);
```

The test remains the Runtime owner. Removing the widget does not close the
Runtime; `TestRuntime` teardown does. Use a `MaterialApp` inside `child` when the
screen needs Material localization, theme, navigation, or Scaffold behavior.

## Deterministic concurrency

Use `TestGate` and `TestSignal` instead of sleeps:

```dart
final gate = TestGate<User>();
final command = commands<User, UserFailure>(
  () => Effect.result((_) => gate.future),
);
final probe = EffectCommandProbe(command);

final execution = command.execute();
await probe.waitFor<EffectCommandRunning<User, UserFailure>>();

gate.complete(user);
await execution;
expect(expectCommandSuccess(command.value), user);
```

The same pattern can verify `drop`, `latest`, queue order, interruption, retained
previous data, and physical work that continues after a logical cancellation.

## Ownership and teardown

Each helper owns only its own listeners and waiters:

- `EffectCommandProbe.dispose()` does not dispose the Command;
- `EffectCommandListenerProbe` does not own the widget or Command;
- `BetterEffectTestApp` does not close the Runtime;
- `TestRuntime.close()` closes the Runtime and its recording observer.

The ViewModel or `EffectCommands` owner remains responsible for Command
disposal. A typical test cleanup is:

```dart
addTearDown(() async {
  probe.dispose();
  viewModel.dispose();
  await harness.close();
});
```

Call `harness.assertNoActiveExecutions()` after releasing all gates to catch a
test that observed a logical result while leaving physical work running.
