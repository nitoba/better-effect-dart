# better_effect_flutter example

A small Flutter MVVM task app demonstrating:

- contextual repositories inside `Effect.result`;
- `EffectCommand0` and typed-input `EffectCommand`;
- drop/latest/queue execution policies;
- one-shot SnackBar listeners;
- typed failure versus unexpected defect handling;
- ViewModel-owned command disposal;
- a long-lived application Runtime without a global injector.

From this directory:

```bash
flutter pub get
flutter test
```

To generate platform folders for interactive execution:

```bash
flutter create . --platforms=android,ios,web,linux,macos,windows
flutter run
```
