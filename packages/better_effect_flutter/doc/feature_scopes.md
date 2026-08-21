# Feature scopes

`BetterEffectFeatureScope` owns a child Runtime for one Flutter subtree. Use it when a feature needs services/resources shared by several ViewModels or Commands but shorter-lived than the application Runtime.

```dart
BetterEffectFeatureScope(
  module: checkoutModule,
  label: 'checkout',
  loadingBuilder: (_) => const CheckoutSplash(),
  errorBuilder: (context, error, stackTrace, retry) {
    return CheckoutStartupError(onRetry: retry);
  },
  builder: (_) => const CheckoutFlow(),
)
```

## Lifecycle

The widget reads the nearest `BetterEffectScope`, forks its Runtime, and exposes a new `BetterEffectScope` containing the child Runtime and a matching `EffectCommands` instance.

The child is closed when the feature leaves the tree or intentionally restarts. The parent Runtime is never closed by the feature scope.

Startup is generation-safe: if an older asynchronous fork completes after the widget has restarted or changed parents, that stale Runtime is closed instead of being published into the subtree.

## Restart behavior

A fresh child environment is created when the effective parent Runtime changes or when `module`, `label`, or `restartKey` changes.

```dart
BetterEffectFeatureScope(
  module: editorModule,
  restartKey: documentId,
  builder: (_) => const EditorScreen(),
)
```

The old child is closed before the new Runtime becomes authoritative.

## ViewModels and Commands

`EffectViewModelBuilder` observes the nearest `EffectCommands`. Replacing the feature Runtime also replaces the Commands boundary, so owned ViewModels are recreated automatically and their Commands are disposed with the old environment.

No additional state-management framework is introduced.

## Loading, failure and retry

While the child starts, `loadingBuilder` is rendered when provided. Startup defects are exposed to `errorBuilder` together with the original stack trace and a generation-safe `retry` callback.

```dart
errorBuilder: (context, error, stackTrace, retry) {
  return StartupFailureView(
    error: error,
    onRetry: retry,
  );
},
```

## Nested feature scopes

Feature scopes can be nested. The inner scope reads the nearest child Runtime as its parent, so resolution naturally becomes:

```text
execution Module
      ↓
inner feature Runtime
      ↓
outer feature Runtime
      ↓
application Runtime
```

## Shutdown policy

`gracePeriod` and `interruptExecutionsBeforeClose` reuse `Runtime.close` semantics. Child work remains physically owned until its execution and resource cleanup finish.

Use a feature scope for feature-length ownership. Keep application-wide services on the root Runtime and use `runWith` for one-execution temporary dependencies.
