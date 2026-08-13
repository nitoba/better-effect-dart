# better_effect_flutter architecture

## Position in Flutter MVVM

```text
View
  - renders state
  - sends user events
  - performs presentation side effects through listeners

ViewModel
  - owns presentation state
  - exposes EffectCommands
  - does not receive every Repository used by every action

EffectCommand
  - owns UI execution state
  - runs an Effect through Runtime
  - maps Exit to sealed UI states
  - coordinates repeated executions

Effect
  - composes application behavior
  - resolves contextual dependencies
  - propagates typed failures
  - owns execution-scoped resources

Repository / UseCase
  - returns Effects or ResultDart values
  - coordinates domain and data operations

Service
  - isolates HTTP, files, plugins, databases, and platform APIs

Module / Runtime
  - builds the environment
  - resolves dependencies
  - owns application-scoped resources
```

## Unidirectional flow

```text
UI event
  ↓
EffectCommand.execute(input)
  ↓
Runtime.runExit(effect)
  ↓
Effect uses Repository / UseCase / Service
  ↓
ExitSuccess | ExitFailure | ExitDefect | ExitInterrupted
  ↓
EffectCommandState
  ↓
Builder renders, Listener performs one-shot UI effects
```

## Why EffectCommand is separate from Effect

An Effect is a lazy application program. It should not know Flutter, Widgets,
`ChangeNotifier`, loading indicators, SnackBars, or navigation.

An EffectCommand is presentation infrastructure. It converts one Effect
execution into observable state, protects the View against duplicate taps and
stale completions, and preserves typed failure/defect/interruption semantics.

The separation keeps `better_effect` usable in pure Dart CLIs, servers, workers,
and tests.

## Why the ViewModel receives EffectCommands

Traditional constructor injection remains useful for stable object-level
collaborators. Contextual Effects solve a different problem: a dependency can be
requested by the operation that actually needs it.

```dart
Effect<User, AppFailure> loadUser(UserId id) => .result((use) async {
  final users = use<UserRepository>();
  return use.unwrap(users.findById(id));
});
```

The ViewModel therefore needs only a Runtime-bound command factory:

```dart
HomeViewModel(EffectCommands commands)
```

This avoids a growing constructor containing repositories used by only one
Command while keeping the dependency local to executable code. A future
`better_effect_analyzer` can restore graph visibility in the editor by listing
each `use<T>()` requirement.

## Typed failure versus defect

Expected failures remain in the Effect error channel:

```dart
Effect<User, UserFailure>
```

They become:

```dart
EffectCommandFailure<User, UserFailure>
```

Unexpected exceptions, programming errors, missing registrations, and cleanup
failures become:

```dart
EffectCommandDefect<User, UserFailure>
```

A View can show a domain-specific message for a typed failure while reporting a
defect to crash analytics without pretending both are the same category.

## Command lifecycle

```text
Provider / EffectViewModelBuilder creates ViewModel
  ↓
ViewModel creates Commands
  ↓
View removed
  ↓
ViewModel.dispose()
  ↓
Command.dispose()
```

`EffectViewModel` uses `EffectCommandOwner` to dispose Commands in reverse
creation order. Disposal interrupts ownership of an active command result and
completes waiting callers with `ExitInterrupted`.

The application Runtime is owned separately by `BetterEffectProvider`,
`BetterEffectBootstrap`, or the caller of `BetterEffectProvider.value`.

## Execution policies

```text
drop
  repeated request ─────► receives active Future
  duplicate work ───────► not started

latest
  old request ──────────► continues in background
  stale completion ─────► cannot update UI state
  newest request ───────► authoritative

queue
  request 1 ─► request 2 ─► request 3
  one authoritative execution at a time
```

These policies are presentation-level coordination. They do not alter the core
Effect semantics or claim fiber-style cancellation for ordinary Dart Futures.

## One-shot UI events

Command state remains durable and renderable. Presentation effects such as
navigation and SnackBars are delivered from revisions:

```text
state revision 7 emitted
  ↓
EffectCommandListener consumes revision 7 once
  ↓
parent rebuilds
  ↓
revision remains 7, listener does not repeat the side effect
```

This removes the need to mutate the ViewModel with `clearError()` after every
presentation event.

## No global injector

`BetterEffectScope` stores a Runtime for a Flutter subtree, but Widgets should
normally know only their ViewModel. `BuildContext.effectCommands` is intended
for ViewModel factories. Business dependencies remain inside Effects through
`use<T>()`.

`readEffectService<T>()` is restricted by convention to composition boundaries
where a third-party framework needs a concrete object.
