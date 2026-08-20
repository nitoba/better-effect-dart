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


## Execution and trigger policies

```text
input invocation
  ↓
TriggerPolicy: immediate | debounce | throttle
  ↓
CommandPolicy: drop | latest | queue
  ↓
managed EffectExecution
  ↓
visible state authority + caller Exit
```

The trigger stage controls when an input is eligible. The execution
stage controls active/queued work. Combining them keeps one
`EffectCommand` abstraction while supporting cancel-previous,
leading/trailing timing, bounded queues, and overflow behavior.

Policy rejection or replacement completes the affected caller with
`ExitInterrupted`; it is not represented as a domain failure. Timed
policies use the contextual `EffectClock`, and their timers are
managed Runtime executions so shutdown and disposal share the same
cooperative ownership model.

Existing `EffectCommandConcurrency` values remain compatibility
shorthands for the corresponding immediate policies.

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


## Selection and rendering boundaries

`EffectCommandBuilder` remains the full-state rendering boundary and
can optionally apply `buildWhen(previous, current)`. A rejected build
transition does not consume the state; it becomes the baseline for the
next comparison while the subtree keeps rendering its last accepted
state.

`EffectCommandSelector` projects either `EffectCommandState` or the
read-only `EffectCommandSnapshot` into a strongly typed value. Snapshot
notifications include queue and pending-count changes that are not
presentation-state revisions. They do not notify `EffectCommandListener`
and therefore cannot repeat navigation, SnackBars, or analytics.

Selector equality is local to rendering. It never mutates Command state,
changes caller outcomes, or changes execution ownership.
