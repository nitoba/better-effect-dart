# Analysis architecture

`better_effect_analyzer` uses two layers deliberately.

## Analysis Server plugin

The plugin is loaded by the Dart Analysis Server through `lib/main.dart`. It
registers local rules that can be evaluated while a single resolved library is
being visited. These diagnostics appear in IDEs and in `dart analyze` or
`flutter analyze`.

Local rules cover discarded Effects, unawaited EffectContext operations,
missing Binding type arguments, Binding compatibility, direct duplicate
registrations, and optional Flutter MVVM boundaries.

## Whole-project graph checker

The CLI builds an `AnalysisContextCollection`, resolves every Dart unit under
`lib` (and optionally `test`), indexes classes, contextual service requests,
constructor tear-offs, and Module declarations, and then validates selected
root Modules.

This separate pass is necessary because a normal rule does not own a stable
whole-workspace graph across unrelated libraries.

## Identity

A service is indexed by its resolved Dart type plus its optional
`ServiceKey<T>`. Constructor-injected dependencies use the default identity;
contextual calls can retain a named key.

## Dependency sources

For every provider, the checker combines:

1. required, non-nullable constructor parameters;
2. `use<T>()`, `use.service<T>()`, `Services.get<T>()`, and
   `Effect.service<T>()` calls, including `.service<T>()` dot shorthands, in the implementation class;
3. service requests in a resource acquisition callback.

The result is validated against the flattened root Module after spreads,
`Module.merge`, and `overrideWith` are applied.
