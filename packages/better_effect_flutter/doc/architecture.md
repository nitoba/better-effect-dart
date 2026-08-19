# better_effect_flutter architecture

## Position in Flutter MVVM

```text
View
  - renders state and sends user events
ViewModel
  - owns presentation state and exposes EffectCommands
EffectCommand
  - runs an Effect through Runtime and maps Exit to UI state
Effect
  - composes application behavior and resolves contextual dependencies
Repository / UseCase
  - coordinates domain and data operations
Service
  - isolates HTTP, files, plugins, databases, and platform APIs
Module / Runtime
  - builds the environment and owns application-scoped resources
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

An Effect is a lazy application program and does not know Flutter, Widgets,
loading indicators, SnackBars, or navigation. An EffectCommand is presentation
infrastructure: it converts one Effect execution into observable state, guards
against duplicate taps and stale completions, and preserves typed failure,
defect, and interruption semantics.

## ViewModel and command lifecycle

The ViewModel receives a Runtime-bound `EffectCommands` factory instead of every
Repository used by every action. Commands are disposed in reverse creation
order when the ViewModel is disposed. The application Runtime is owned
separately by `BetterEffectProvider`, `BetterEffectBootstrap`, or the caller.

## Execution policies

```text
drop    duplicate work is not started
latest  stale completions cannot update UI state
queue   one authoritative execution runs at a time
```

These policies coordinate presentation updates. They do not claim fiber-style
cancellation for arbitrary Dart Futures.

## Typed failures and one-shot events

Expected domain failures remain typed in the Effect error channel and become
`EffectCommandFailure`. Unexpected exceptions, programming errors, missing
registrations, and cleanup failures become `EffectCommandDefect`.

Command state remains durable and renderable. Navigation and SnackBars are
delivered from revisions so rebuilding a widget does not repeat a consumed
side effect.

`BetterEffectScope` stores a Runtime for a Flutter subtree, but Widgets should
normally know only their ViewModel. Business dependencies remain inside Effects
through `use<T>()` rather than a global injector.
