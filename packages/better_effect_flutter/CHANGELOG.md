## Unreleased

- Added the repository-level normative semantic contract and an independent
  cross-package conformance suite for Command authority, one-shot delivery, and
  Flutter Runtime ownership alongside the core lifecycle rules.
- Semantic compatibility changes now require the matching conformance scenario,
  affected package changelog entries, and a semantic migration ledger entry.
- Added `BetterEffectFeatureScope` for feature-owned child Runtimes with
  loading/error/retry startup, nested feature environments, and generation-safe
  restart behavior.
- ViewModels and Commands inside a feature automatically bind to the child
  environment, while feature disposal never closes the parent Runtime.
- Added `EffectCommandSelector` with strongly typed state and snapshot selection.
- Added default `==` and custom equality strategies for selected values.
- Added `EffectCommandBuilder.buildWhen` and matching Consumer support.
- Added read-only `EffectCommandSnapshot` updates for pending, queued, and trigger-pending counts without artificial state revisions.

- Added immutable `CommandPolicy.drop`, `latest`, and `queue`
  coordination without adding new Command classes.
- Added optional cooperative previous-execution interruption for
  `CommandPolicy.latest(cancelPrevious: true)`.
- Added typed-input debounce and throttle triggers driven by the
  contextual `EffectClock` service.
- Added bounded FIFO queues with explicit reject-newest,
  drop-newest, and drop-oldest overflow decisions.
- Policy replacement and rejection use `ExitInterrupted` instead
  of inventing domain failures or a new Exit variant.
- Added `EffectCommandPolicyEvent`, shared/local policy observers,
  `EffectCommandPolicyProbe`, and deterministic ManualEffectClock
  regression coverage.
- Existing `EffectCommandConcurrency` call sites remain source
  compatible and translate exactly to the corresponding policies.

## 0.3.0

- Added `package:better_effect_flutter/testing.dart`, re-exporting the core
  testing toolkit with Flutter-specific Command and widget helpers.
- Added `EffectCommandProbe` waits and history assertions, typed sealed-state
  extractors, `EffectCommandListenerProbe` for one-shot delivery, and
  `BetterEffectTestApp` for externally owned Runtime widget tests.

## 0.2.0

- Effect Commands now start work through core `EffectExecution` handles.
- Command cancellation and disposal request cooperative core interruption while
  retaining `onCancel` as an optional adapter hook.
- Command debug labels now flow into Runtime execution metadata.
- Existing `drop`, `latest`, and `queue` state-authority semantics remain
  unchanged; `latest` does not cancel stale work unless a future policy opts in.
- Runtime shutdown interruption now reaches visible Command state.
- Added explicit `BetterEffectRuntimeOwnership` values for external, widget, and
  application-owned Runtimes.
- Added `BetterEffectLifecyclePolicy` for widget disposal, application exit,
  cooperative interruption, and shutdown grace periods.
- Providers and bootstrap roots now remove a Runtime from the widget tree before
  lifecycle-triggered shutdown begins.
- Runtime replacement closes the previous owned Runtime exactly once, while
  `BetterEffectProvider.value` never assumes ownership.
- `BetterEffectBootstrap` now restarts when `backendFactory` changes and closes
  stale startup attempts safely.
- Existing `closeRuntimeOnDispose` and `closeRuntimeOnDetach` constructor
  arguments remain as deprecated migration parameters.
- Added deterministic regression coverage for queue cancellation, retained
  physical ownership, Command disposal versus Runtime shutdown, repeated
  cancellation races, and stale `latest` completions.

## 0.1.1

- Expanded the package documentation with complete bootstrap, Command,
  ViewModel, widget, lifecycle, testing, and concurrency guidance.
- Updated the hosted `better_effect` dependency to `0.1.1`.

## 0.1.0

- Added `EffectCommand0` and typed-input `EffectCommand`.
- Added sealed idle/running/success/failure/defect/interrupted UI states.
- Added drop, latest, and queue execution policies.
- Added one-shot `EffectCommandListener`, builder, and consumer widgets.
- Added `EffectCommands`, `EffectViewModel`, and automatic command disposal.
- Added `BetterEffectScope`, provider, bootstrap widget, and app bootstrap helper.
- Added an MVVM task application example and Flutter test suite.
