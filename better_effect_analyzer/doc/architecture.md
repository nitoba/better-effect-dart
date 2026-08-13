# Analysis architecture

`better_effect_analyzer` uses two layers deliberately.

## Analysis Server plugin

The plugin is loaded through `lib/main.dart` and registers local rules that can
be evaluated while a single resolved library is visited. These diagnostics
appear in IDEs and in `dart analyze` or `flutter analyze`.

Local rules cover discarded Effects, unawaited EffectContext operations, missing
Binding type arguments, Binding compatibility, direct duplicate registrations,
and optional Flutter MVVM boundaries.

## Whole-project graph checker

The CLI builds an `AnalysisContextCollection`, resolves Dart units under `lib`
(and optionally `test`), indexes classes, contextual service requests,
constructor tear-offs, and Module declarations, and validates selected root
Modules. This separate pass is necessary because a normal rule does not own a
stable whole-workspace graph across unrelated libraries.

## Identity and dependency sources

A service is indexed by its resolved Dart type plus its optional `ServiceKey<T>`.
For every provider, the checker combines required non-nullable constructor
parameters, contextual requests such as `use<T>()` and `Services.get<T>()`, and
service requests in resource acquisition callbacks. The result is validated
against the flattened root Module after spreads, `Module.merge`, and
`overrideWith` are applied.
