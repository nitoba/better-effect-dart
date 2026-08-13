# better_effect_flutter

**Typed Effects behind your Flutter MVVM Commands.**

`better_effect_flutter` integrates the Dart-only `better_effect` runtime with
Flutter's MVVM + Command style without turning the Effect runtime into a state
management package.

```text
View
  │ executes and observes
  ▼
EffectCommand<Input, Output, Failure>
  │ Runtime.runExit(effect)
  ▼
Effect<Output, Failure>
  │
  ├── use<Repository>()
  ├── use<Service>()
  ├── use.unwrap(...)
  ├── use.result(...)
  └── use.fail(...)
          │
          ▼
Module + Runtime + AutoInjector + Scope
```

The package deliberately keeps each responsibility separate:

- `better_effect` describes and composes lazy application operations;
- `EffectCommand` turns one operation into observable Flutter state;
- a ViewModel owns Commands and presentation state;
- the View renders state and emits user events;
- Provider, Riverpod, BLoC, Signals, MobX, or plain `ChangeNotifier` remain
  optional choices around that flow.

It does not depend on `result_command` and does not collapse typed failures into
`Exception`.

## Requirements

- Dart 3.10 or newer;
- Flutter 3.38 or newer;
- `better_effect` 0.1.x.

Recommended workspace:

```text
my_workspace/
├── better_effect/
└── better_effect_flutter/
```

Published packages use the hosted core dependency:

```yaml
dependencies:
  better_effect: ^0.1.0
```

When working in this repository, the checked-out core package is selected by
`pubspec_overrides.yaml`; that local-only file is not uploaded to pub.dev.

## Install in an application

```yaml
dependencies:
  better_effect_flutter: ^0.1.0
```

One import exposes the Flutter integration and re-exports the core API:

```dart
import 'package:better_effect_flutter/better_effect_flutter.dart';
```

## Quick start

### 1. Describe normal Dart contracts

```dart
sealed class AuthFailure implements Exception {
  const AuthFailure();
}

final class InvalidCredentials extends AuthFailure {
  const InvalidCredentials();
}

typedef LoginInput = ({String email, String password});

abstract interface class AuthRepository {
  Effect<Session, AuthFailure> login(LoginInput input);
}
```

### 2. Request dependencies where an Effect uses them

```dart
final class AuthRepositoryLive implements AuthRepository {
  @override
  Effect<Session, AuthFailure> login(LoginInput input) => .result((use) async {
    final api = use<AuthApi>();

    return use.tryAsync(
      () => api.login(input),
      onError: (error, stackTrace) => const InvalidCredentials(),
    );
  });
}
```

`AuthApi` is not forced into the repository constructor. The dependency is born
from the code that uses it:

```dart
final api = use<AuthApi>();
```

Constructor injection from the core package remains available when it is a
better fit. Both styles can coexist.

### 3. Configure the environment

```dart
final appModule = Module([
  .provide<AuthApi>(AuthApiLive.new),
  .provide<AuthRepository>(AuthRepositoryLive.new),
]);
```

### 4. Bootstrap Flutter

```dart
Future<void> main() {
  return runBetterEffectApp(
    module: appModule,
    app: const App(),
  );
}
```

This creates one long-lived Runtime, installs a `BetterEffectScope`, and closes
the Runtime when the Flutter root is disposed or detached.

### 5. Expose Commands from the ViewModel

```dart
final class LoginViewModel extends EffectViewModel {
  LoginViewModel(super.commands) {
    login = commandWithInput(
      _login,
      debugLabel: 'LoginViewModel.login',
      keepPreviousData: false,
    );
  }

  late final EffectCommand<
    LoginInput,
    Session,
    AuthFailure
  > login;

  Effect<Session, AuthFailure> _login(LoginInput input) => .result((use) async {
    final repository = use<AuthRepository>();

    return use.unwrap(
      repository.login(input),
    );
  });
}
```

The ViewModel receives only `EffectCommands`. It does not receive the Runtime,
Module, injector, `AuthRepository`, or `AuthApi`.

### 6. Create the ViewModel at the Flutter boundary

Without another state package:

```dart
EffectViewModelBuilder<LoginViewModel>(
  create: (_, commands) => LoginViewModel(commands),
  builder: (context, viewModel, child) {
    return LoginPage(viewModel: viewModel);
  },
)
```

With Provider:

```dart
ChangeNotifierProvider<LoginViewModel>(
  create: (context) => LoginViewModel(
    context.effectCommands,
  ),
  child: const LoginPage(),
)
```

`context.effectCommands` is a non-listening lookup, so it is suitable for object
factories. `EffectViewModelBuilder` uses `watchEffectCommands()` internally and
recreates its ViewModel if the scoped Runtime changes.

## EffectCommand

An Effect Command is a `ValueListenable<EffectCommandState<A, E>>` backed by a
long-lived Runtime.

Without input:

```dart
late final EffectCommand0<HomeData, AppFailure> load;

load = command(_load);
```

With input:

```dart
late final EffectCommand<UserId, Unit, AppFailure> deleteUser;

deleteUser = commandWithInput(_deleteUser);
```

For multiple logical arguments, use a named record instead of arity-specific
`Command2`, `Command3`, and `Command4` classes:

```dart
late final EffectCommand<
  ({String email, String password}),
  Session,
  AuthFailure
> login;

await login.execute((
  email: email,
  password: password,
));
```

Commands are callable objects, so this is equivalent:

```dart
await login((email: email, password: password));
```

`execute()` returns `Future<Exit<A, E>>`, allowing imperative callers to inspect
the exact outcome while the View observes the same execution as state.

## Sealed UI states

```text
EffectCommandIdle<A, E>
EffectCommandRunning<A, E>
EffectCommandSuccess<A, E>
EffectCommandFailure<A, E>
EffectCommandDefect<A, E>
EffectCommandInterrupted<A, E>
```

The distinction is intentional:

```text
EffectCommandFailure<E>
→ expected, typed application failure

EffectCommandDefect
→ unhandled exception, programming error, missing dependency, cleanup failure

EffectCommandInterrupted
→ the Command stopped owning the active execution result
```

Use exhaustive patterns:

```dart
Widget render(EffectCommandState<Session, AuthFailure> state) {
  return switch (state) {
    EffectCommandIdle() => const Text('Ready'),
    EffectCommandRunning() => const CircularProgressIndicator(),
    EffectCommandSuccess(:final value) => Text(value.userEmail),
    EffectCommandFailure(:final error) => AuthError(error: error),
    EffectCommandDefect(:final defect) => UnexpectedError(error: defect),
    EffectCommandInterrupted() => const Text('Interrupted'),
  };
}
```

Useful command getters include:

```dart
command.value
command.isRunning
command.data
command.error
command.lastSuccess
command.lastFailure
command.lastExit
command.lastDefect
command.resultOrNull
command.pendingCount
command.queuedCount
```

When `keepPreviousData` is true, running, failure, defect, and interruption
states retain the latest successful value through `state.dataOrNull`.

## Render command state

```dart
EffectCommandBuilder<Session, AuthFailure>(
  command: viewModel.login,
  builder: (context, state, child) {
    return FilledButton(
      onPressed: state.isRunning
          ? null
          : () {
              viewModel.login.execute((
                email: email,
                password: password,
              ));
            },
      child: state.isRunning
          ? const CircularProgressIndicator()
          : const Text('Sign in'),
    );
  },
)
```

`EffectCommandBuilder` is a thin typed wrapper over `ValueListenableBuilder`.

## One-shot presentation effects

Use `EffectCommandListener` for navigation, dialogs, SnackBars, analytics, and
other effects that should happen once per execution:

```dart
EffectCommandListener<Session, AuthFailure>(
  command: viewModel.login,
  onSuccess: (context, session) {
    Navigator.of(context).pushReplacementNamed('/home');
  },
  onFailure: (context, failure, previous) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$failure')),
    );
  },
  onDefect: (context, defect, stackTrace, previous) {
    reportUnexpectedError(defect, stackTrace);
  },
  onInterrupted: (context, previous) {
    debugPrint('Login interrupted');
  },
  child: const LoginForm(),
)
```

Each visible state has a monotonically increasing `revision`. A listener
consumes each revision once, so the View does not need to call `clearError()` or
`clearResult()` after navigating or showing a SnackBar.

`EffectCommandConsumer` combines builder and listener behavior for one subtree.

## Repeated execution policies

### Drop — safe default

```dart
save = command(
  _save,
  concurrency: .drop,
);
```

A repeated call while running receives the same Future and does not start
another Effect. The input Command retains the input that actually started.

Appropriate for submit, refresh, and destructive actions.

### Latest — stale results cannot replace newer state

```dart
search = commandWithInput(
  _search,
  concurrency: .latest,
);
```

Every invocation starts. Only the latest authoritative execution can update the
Command state. Older callers still receive their own `Exit`, and older Effect
scopes still finish normally.

Appropriate for search and rapidly changing filters.

### Queue — preserve request order

```dart
toggle = commandWithInput(
  _toggle,
  concurrency: .queue,
);
```

Executions run serially in request order. Appropriate for ordered writes,
upload steps, and rapid toggles whose intent must not be dropped.

## Cooperative interruption

Dart Futures are not generally cancellable. Calling:

```dart
command.cancel();
```

immediately:

- publishes `EffectCommandInterrupted`;
- completes the Future returned by `execute()` with `ExitInterrupted`;
- ignores the eventual stale completion;
- completes queued requests as interrupted by default.

Supply `onCancel` to signal an API that supports cooperative cancellation:

```dart
upload = commandWithInput(
  _upload,
  onCancel: cancelToken.cancel,
);
```

Use `cancel(clearQueued: false)` to interrupt the active request and continue
with the next queued request.

## Retry and reset

```dart
await command.retry();
command.reset();
command.clear();
```

Input Commands remember their latest accepted input. With `.drop`, an input that
was dropped while another request was active does not replace the retry input.

`reset()` returns to idle and can retain previous data. `clear()` also removes
cached success and failure values. Both return false while authoritative or
queued work exists.

## Global command observation

```dart
Future<void> main() {
  return runBetterEffectApp(
    module: appModule,
    observer: (transition) {
      debugPrint('$transition');
    },
    app: const App(),
  );
}
```

`EffectCommandTransition` includes the previous state, current state, timestamp,
and optional `debugLabel`. This is useful for logging, tracing, analytics, and a
future DevTools integration.

A command-specific `stateObserver` can project successful Command state into a
ViewModel:

```dart
load = command(
  _load,
  stateObserver: (state) {
    if (state case EffectCommandSuccess(:final value)) {
      items = value;
      notifyListeners();
    }
  },
);
```

Observer failures are reported through `FlutterError` and do not replace the
Effect's typed outcome.

## Runtime bootstrap options

### Application root

```dart
await runBetterEffectApp(
  module: appModule,
  app: const App(),
  startupErrorBuilder: (error, stackTrace) {
    return StartupFailureApp(error: error);
  },
);
```

### Declarative bootstrap

```dart
runApp(
  BetterEffectBootstrap(
    module: appModule,
    loadingBuilder: (_) => const SplashScreen(),
    errorBuilder: (context, error, stackTrace, retry) {
      return StartupError(
        error: error,
        onRetry: retry,
      );
    },
    builder: (_) => const App(),
  ),
);
```

`BetterEffectBootstrap` accepts a `backendFactory`, so retries always receive a
fresh resolver backend. Change `restartKey` to intentionally rebuild the
Runtime.

### Existing Runtime

```dart
BetterEffectProvider(
  runtime: runtime,
  child: const App(),
)
```

The default provider owns and closes the Runtime. Use:

```dart
BetterEffectProvider.value(
  runtime: externallyOwnedRuntime,
  child: const Feature(),
)
```

when another owner controls its lifecycle.

## Flutter composition-boundary helpers

```dart
final commands = context.effectCommands;       // non-listening
final commands = context.watchEffectCommands();
final runtime = context.effectRuntime;

final result = await context.runEffect(program);
final exit = await context.runEffectExit(program);
```

`readEffectService<T>()` exists for route/provider factories and adapters. It is
not intended as a replacement for contextual `use<T>()` inside business code.

## Existing ViewModel base classes

Use the mixin when a class cannot extend `EffectViewModel`:

```dart
final class HomeViewModel extends ChangeNotifier
    with EffectCommandOwner {
  HomeViewModel(EffectCommands commands) {
    load = ownCommand(commands(_load));
  }

  late final EffectCommand0<HomeData, AppFailure> load;
}
```

Owned Commands are disposed in reverse creation order with the ViewModel.

## Testing

Override services at the Module boundary and run the real Command + Effect flow:

```dart
final runtime = await appModule.overrideWith([
  .instance<AuthRepository>(FakeAuthRepository()),
]).start();

final viewModel = LoginViewModel(
  EffectCommands(runtime),
);

final exit = await viewModel.login.execute((
  email: 'bruno@example.com',
  password: 'secret',
));

expect(exit, isA<ExitSuccess<Session, AuthFailure>>());

viewModel.dispose();
await runtime.close();
```

The package includes unit tests, widget tests, lifecycle tests, and a complete
MVVM task example.

## Example

```bash
cd example
flutter pub get
flutter test
flutter create . --platforms=android,ios,web
flutter run
```

The example demonstrates contextual Repository/Service resolution, typed
failure propagation, initial loading, one-shot SnackBars, and drop/latest/queue
coordination without a global injector.

## Package boundary

`better_effect_flutter` intentionally does not provide:

- a second Result type;
- a global service locator;
- a replacement for Provider/Riverpod/BLoC/Signals;
- fake cancellation guarantees for arbitrary Futures;
- a `better_effect_result_command` adapter.

Its responsibility is narrower:

> Execute typed, dependency-aware Effects as ergonomic Flutter MVVM Commands.
