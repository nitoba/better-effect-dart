## Unreleased

- Effect Commands now start work through core `EffectExecution` handles.
- Command cancellation and disposal request cooperative core interruption while
  retaining `onCancel` as an optional adapter hook.
- Command debug labels now flow into Runtime execution metadata.
- Existing `drop`, `latest`, and `queue` state-authority semantics remain
  unchanged; `latest` does not cancel stale work unless a future policy opts in.
- Runtime shutdown interruption now reaches visible Command state.

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
