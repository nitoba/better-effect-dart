# better_effect monorepo

This repository contains three independently versioned Dart and Flutter
packages. Each package has its own `pubspec.yaml`, changelog, tests, and pub.dev
release workflow.

## Packages

| Package | Purpose | Current version |
| --- | --- | --- |
| [`better_effect`](packages/better_effect) | Typed effects, dependency injection, resource scopes, and error propagation | `0.3.0` |
| [`better_effect_flutter`](packages/better_effect_flutter) | Flutter MVVM integration, commands, scopes, and widgets | `0.3.0` |
| [`better_effect_analyzer`](packages/better_effect_analyzer) | Static analysis and whole-project dependency-graph diagnostics | `0.3.0` |

The Flutter sample application lives at
[`packages/better_effect_flutter/example`](packages/better_effect_flutter/example).
It stays beside the package so the published package can expose a runnable
example without creating a separate release unit.

## Repository layout

```text
packages/
  better_effect/
  better_effect_flutter/
    example/
  better_effect_analyzer/
.github/
  workflows/
apps/
  docs/                 # Next.js + Fumadocs
```

There is intentionally no root Dart package. Dependencies and lockfiles belong
to the package or example that owns them, which keeps package publication and
dependency resolution independent.

## Documentation site

The public documentation site lives in [`apps/docs`](apps/docs) and is built
with Next.js and Fumadocs. It has its own Node dependencies and does not change
the Dart package publication flow:

```bash
cd apps/docs
npm install
npm run dev
```

Use `npm run build` to validate the production build.

## Local development

Run commands from the package being changed:

```bash
cd packages/better_effect
dart pub get
dart analyze --fatal-infos
dart test
dart pub publish --dry-run
```

```bash
cd packages/better_effect_flutter
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter pub publish --dry-run --ignore-warnings
```

The Flutter package includes a separate example check:

```bash
cd packages/better_effect_flutter/example
flutter pub get
flutter analyze --fatal-infos
flutter test
```

For local monorepo work, the ignored `pubspec_overrides.yaml` files replace
hosted package dependencies with sibling paths. They are not included in pub
archives. The example's `pubspec.lock` is tracked because it belongs to the
example application; publishable package lockfiles remain ignored.

## Independent releases

Publishing is triggered only by a package-specific tag:

```bash
git tag better_effect-v0.3.0
git push origin better_effect-v0.3.0
```

Use `better_effect_flutter-v{{version}}` and
`better_effect_analyzer-v{{version}}` for the other packages. A tag for one
package cannot start another package's workflow. Before the first automated
release, configure the matching tag pattern in that package's pub.dev Admin
settings as described in [`.github/RELEASE.md`](.github/RELEASE.md).
