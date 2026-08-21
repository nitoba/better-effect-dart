# better_effect conformance

Internal, non-published package that executes the normative contract in
[`../../SEMANTICS.md`](../../SEMANTICS.md) against `better_effect` and
`better_effect_flutter` together.

Run it independently from ordinary unit tests:

```bash
cd packages/better_effect_conformance
flutter pub get
flutter analyze --fatal-infos
flutter test
```

The suite uses rule IDs from the normative document. Its registry fails when a
stable rule is missing an executable scenario or when a scenario is registered
more than once. Race-sensitive scenarios use deterministic gates, manual clocks,
Runtime events, or Flutter's fake clock instead of wall-clock sleeps.
