# better_effect_flutter

[![pub package](https://img.shields.io/pub/v/better_effect_flutter.svg)](https://pub.dev/packages/better_effect_flutter)
[![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A53.38.0-02569B.svg)](https://flutter.dev/)

Typed Effects behind Flutter MVVM Commands.

`better_effect_flutter` connects the Dart-only
[better_effect](https://pub.dev/packages/better_effect) runtime to Flutter
widgets and ViewModels. It turns a typed `Effect<Output, Failure>`
into an observable
`EffectCommandState<Output, Failure>`, while keeping
dependency resolution, expected failures, and unexpected defects separate.

The package is intentionally focused:

- `better_effect` describes and runs lazy, dependency-aware Effects;
- `EffectCommand` executes one Effect through a long-lived Runtime;
- `EffectViewModel` owns Commands and presentation state;
- `EffectCommandBuilder` renders state and
  `EffectCommandListener` handles one-shot UI effects;
- `BetterEffectBootstrap` and `BetterEffectProvider` put
  the Runtime in the widget tree.

It does not replace Provider, Riverpod, BLoC, Signals, MobX, or another
state-management package. Those packages can still create and expose ViewModels
in their usual way.

## When it fits

Use this package when a Flutter feature needs:

- typed domain failures instead of a single untyped error flag;
- a separate representation for defects such as missing dependencies or
  programming errors;
- loading, success, failure, defect, and interruption states from one sealed
  hierarchy;
- explicit handling of repeated taps, searches, refreshes, uploads, or ordered
  writes;
- one-shot SnackBars, dialogs, navigation, and analytics without manually
  clearing result flags;
- automatic disposal of Commands with a ViewModel;
- a long-lived `better_effect` Runtime shared by a Flutter subtree.

If an application only needs a simple `FutureBuilder`, or already has
a command abstraction with these semantics, this package may add more structure
than necessary.

## The flow

```text
Flutter app
    │
    ▼
BetterEffectBootstrap / BetterEffectProvider
    │ creates and owns
    ▼
Runtime + EffectCommands
    │ supplied to
    ▼
EffectViewModel
    │ owns
    ▼
EffectCommand<Input, Output, Failure>
    │ executes
    ▼
Effect<Output, Failure>
    │ resolves services with use<T>()
    ▼
Module + Runtime
```

An `EffectCommand` is a
`ValueListenable<EffectCommandState<A, E>>`. The View can
observe the same execution declaratively while imperative code awaits
`execute()` and receives an `Exit<A, E>`.

## Requirements

- Dart 3.10 or newer;
- Flutter 3.38 or newer;
- [`better_effect`](https://pub.dev/packages/better_effect) 0.1.x.

The package re-exports `better_effect`, so most applications need
only one import:

```dart
import 'package:better_effect_flutter/better_effect_flutter.dart';
```

## Installation

```bash
flutter pub add better_effect_flutter
```

Or add it manually:

```yaml
dependencies:
  better_effect_flutter: ^0.1.1
```

During local monorepo development, this repository uses an ignored
`pubspec_overrides.yaml` to point `better_effect` at the
checked-out sibling package. Applications outside this repository should use
the hosted dependency shown above.

## Quick start

The recommended feature shape is ordinary Dart contracts, Effects for
application operations, a Module at the composition root, a ViewModel that
owns Commands, and a View that renders or listens to Command state.

### 1. Define a typed failure and a contract

```dart
sealed class AppFailure implements Exception {
  const AppFailure();
}

final class GreetingFailure extends AppFailure {
  const GreetingFailure(this.message);

  final String message;

  @override
  String toString() => 'GreetingFailure($message)';
}

typedef AppEffect<A extends Object> = Effect<A, AppFailure>;

abstract interface class GreetingService {
  AppEffect<String> greet(String name);
}
```

### 2. Resolve dependencies inside an Effect

```dart
final class GreetingServiceLive implements GreetingService {
  @override
  AppEffect<String> greet(String name) => Effect.tryAsync(
        () async => 'Hello, $name!',
        onError: (error, stackTrace) =>
            GreetingFailure(error.toString()),
      );
}

AppEffect<String> greeting(String name) => Effect.result((use) async {
      final service = use<GreetingService>();
      return use.unwrap(service.greet(name));
    });
```

`use<GreetingService>()` resolves from the Runtime executing this
Effect. It is not a global service locator. Constructor injection from
`better_effect` remains available; both styles can coexist.

### 3. Configure the Module

```dart
final appModule = Module([
  .provide<GreetingService>(GreetingServiceLive.new),
]);
```

### 4. Start the Runtime at the Flutter boundary

When this package owns the application root,
`runBetterEffectApp` is the shortest bootstrap:

```dart
Future<void> main() {
  return runBetterEffectApp(
    module: appModule,
    app: const GreetingApp(),
  );
}
```

It starts one long-lived Runtime, inserts a
`BetterEffectScope`, and closes the Runtime when the provider is
disposed or the Flutter view detaches.

For add-to-app, previews, tests, or a feature root, use the declarative widget:

```dart
runApp(
  BetterEffectBootstrap(
    module: appModule,
    loadingBuilder: (_) => const SplashScreen(),
    errorBuilder: (context, error, stackTrace, retry) {
      return StartupErrorScreen(
        error: error,
        onRetry: retry,
      );
    },
    builder: (_) => const GreetingApp(),
  ),
);
```

### 5. Create a ViewModel and its Command

```dart
final class GreetingViewModel extends EffectViewModel {
  GreetingViewModel(super.commands) {
    greet = commandWithInput<String, String, AppFailure>(
      greeting,
      keepPreviousData: false,
      debugLabel: 'GreetingViewModel.greet',
    );
  }

  late final EffectCommand<String, String, AppFailure> greet;
}
```

The ViewModel receives `EffectCommands`, not the Module, Runtime,
injector, or every service. Commands created through
`EffectViewModel` are automatically disposed with the ViewModel.

### 6. Create the ViewModel at a composition boundary

`EffectViewModelBuilder` is the package's state-management-free
option:

```dart
final class GreetingScreen extends StatelessWidget {
  const GreetingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return EffectViewModelBuilder<GreetingViewModel>(
      create: (_, commands) => GreetingViewModel(commands),
      builder: (_, viewModel, _) => GreetingView(viewModel: viewModel),
    );
  }
}
```

If the app already uses Provider, Riverpod, BLoC, or another adapter, obtain the
scoped factory without listening:

```dart
final viewModel = GreetingViewModel(context.effectCommands);
```

`context.effectCommands` is intended for factories.
`watchEffectCommands()` is the listening form used by lifecycle
adapters such as `EffectViewModelBuilder`.

## Commands

### Commands with and without input

Use `EffectCommand0` for an operation without input:

```dart
late final EffectCommand0<HomeData, AppFailure> load;

load = command<HomeData, AppFailure>(_load);
await load.execute();
```

Use `EffectCommand<I, A, E>` when an operation has one input:

```dart
late final EffectCommand<UserId, Unit, AppFailure> deleteUser;

deleteUser = commandWithInput<UserId, Unit, AppFailure>(_deleteUser);
await deleteUser.execute(userId);
```

For several logical values, use a named record rather than arity-specific
Command2/Command3 types:

```dart
typedef LoginInput = ({String email, String password});

late final EffectCommand<LoginInput, Session, AuthFailure> login;

await login.execute((
  email: email,
  password: password,
));
```

Commands are callable objects, so
`await login(input)` is equivalent to
`await login.execute(input)`.

`execute()` returns `Future<Exit<A, E>>`. The View
observes state while imperative callers can inspect
`ExitSuccess`, `ExitFailure`, `ExitDefect`, or
`ExitInterrupted` directly.

### Create Commands directly

ViewModels normally receive `EffectCommands`, which binds every
Command to the same long-lived Runtime:

```dart
final commands = EffectCommands(runtime);

final load = commands.fromEffect(
  loadHome(),
  debugLabel: 'Home.load',
);

final search = commands.withInput<Query, List<Result>, SearchFailure>(
  (query) => searchEffect(query),
  concurrency: EffectCommandConcurrency.latest,
);
```

Use `EffectViewModel.command` and
`commandWithInput` when the ViewModel can extend
`EffectViewModel`. Use `EffectCommands.call`,
`fromEffect`, or `withInput` when a framework adapter or
an existing base class creates Commands.

## Command state

Every Command exposes this sealed state hierarchy:

| State                      | Meaning                                                                       |
| -------------------------- | ----------------------------------------------------------------------------- |
| `EffectCommandIdle`        | No authoritative execution is running, or the Command was reset.              |
| `EffectCommandRunning`     | An Effect is currently executing.                                             |
| `EffectCommandSuccess`     | The Effect returned a successful value.                                       |
| `EffectCommandFailure`     | The Effect returned an expected, typed failure.                               |
| `EffectCommandDefect`      | An unexpected exception, Error, missing service, or cleanup failure occurred. |
| `EffectCommandInterrupted` | The Command stopped owning the active execution result.                       |

The distinction keeps an expected domain failure separate from a defect:

```dart
Widget render(EffectCommandState<Session, AuthFailure> state) {
  return switch (state) {
    EffectCommandIdle() => const Text('Ready'),
    EffectCommandRunning(:final previous) =>
      previous == null
          ? const CircularProgressIndicator()
          : SessionView(session: previous),
    EffectCommandSuccess(:final value) => SessionView(session: value),
    EffectCommandFailure(:final error, :final previous) =>
      LoginError(error: error, previous: previous),
    EffectCommandDefect(:final defect) => UnexpectedError(error: defect),
    EffectCommandInterrupted(:final previous) =>
      InterruptedView(previous: previous),
  };
}
```

Useful getters include `value`, `isRunning`,
`data`, `error`, `lastSuccess`,
`lastFailure`, `lastExit`, `lastDefect`,
`resultOrNull`, `pendingCount`, and
`queuedCount`.

By default, Commands keep their latest successful value while running or after
a failure. Set `keepPreviousData: false` when the View must clear
data during those states. The retained value is available through
`state.dataOrNull` or `state.previousOrNull`.

## Render state and one-shot effects

### `EffectCommandBuilder`

Use the builder for state-driven rendering. It is a typed wrapper around
Flutter's `ValueListenableBuilder`:

```dart
EffectCommandBuilder<String, AppFailure>(
  command: viewModel.greet,
  builder: (context, state, child) {
    if (state.isRunning && state.dataOrNull == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state case EffectCommandFailure(:final error)) {
      return ErrorView(message: error.toString());
    }

    if (state case EffectCommandDefect(:final defect)) {
      return ErrorView(message: 'Unexpected error: $defect');
    }

    return Text(state.dataOrNull ?? 'Press the button');
  },
)
```

### `EffectCommandListener`

Use the listener for navigation, dialogs, SnackBars, analytics, or other
one-shot presentation effects:

```dart
EffectCommandListener<String, AppFailure>(
  command: viewModel.greet,
  onSuccess: (context, message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  },
  onFailure: (context, failure, previous) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(failure.toString())),
    );
  },
  onDefect: (context, defect, stackTrace, previous) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: defect, stack: stackTrace),
    );
  },
  child: GreetingButton(viewModel: viewModel),
)
```

Each visible state has a monotonically increasing `revision`. A
listener consumes each revision once, so a SnackBar or navigation callback does
not repeat after an unrelated rebuild. Set `fireImmediately: true`
when the state present at mount should also be delivered. Use
`listenWhen` to filter transitions.

### `EffectCommandConsumer`

`EffectCommandConsumer` combines Builder and Listener for one subtree:

```dart
EffectCommandConsumer<String, AppFailure>(
  command: viewModel.greet,
  onSuccess: (context, message) {
    Navigator.of(context).pushNamed('/greeting');
  },
  onFailure: (context, failure, previous) {
    showGreetingError(context, failure);
  },
  builder: (context, state, child) {
    return GreetingButton(
      busy: state.isRunning,
      onPressed: viewModel.greet,
    );
  },
)
```

## Repeated executions

`EffectCommandConcurrency` defines what happens when
`execute` is called while work is already in flight.

### `drop`

```dart
save = command(_save, concurrency: EffectCommandConcurrency.drop);
```

This is the default. A repeated call returns the active Future and does not
start duplicate work. It is appropriate for submit buttons, refresh actions,
and destructive operations.

### `latest`

```dart
search = commandWithInput(
  _search,
  concurrency: EffectCommandConcurrency.latest,
);
```

Every call starts. Only the newest execution may update visible Command state;
older completions cannot overwrite it. Older callers still receive their own
`Exit`. This is useful for search fields and changing filters.

### `queue`

```dart
toggle = commandWithInput(
  _toggle,
  concurrency: EffectCommandConcurrency.queue,
);
```

Calls are executed serially in request order. Use it for ordered writes,
uploads, or toggles where every user intent matters.

## Cancellation, retry, and reset

Dart Futures are not generally cancellable. `command.cancel()` changes
the Command immediately, but it cannot forcefully stop arbitrary work underneath:

```dart
command.cancel();
```

Cancellation:

- publishes `EffectCommandInterrupted`;
- completes the caller's Future with `ExitInterrupted`;
- ignores the eventual stale completion;
- interrupts queued executions by default.

Provide `onCancel` to signal a cooperative API such as a Dio token,
download manager, or isolate:

```dart
upload = commandWithInput(
  _upload,
  onCancel: cancelToken.cancel,
);
```

Use `cancel(clearQueued: false)` to interrupt the active execution and
start the next queued operation.

Commands without input can always retry. Input Commands remember the latest
accepted input:

```dart
await command.retry();
```

With `drop`, an input rejected while another execution is active does
not replace the input used by `retry()`.

`reset()` returns to `EffectCommandIdle` and may retain the
latest successful data. `clear()` also removes cached success and
failure values. Both return `false` while authoritative or queued
work exists.

## Bootstrap and Runtime ownership

### `runBetterEffectApp`

Use this when the package owns the application root:

```dart
Future<void> main() {
  return runBetterEffectApp(
    module: appModule,
    observer: (transition) => debugPrint('$transition'),
    startupErrorBuilder: (error, stackTrace) {
      return StartupErrorApp(error: error, stackTrace: stackTrace);
    },
    app: const App(),
  );
}
```

The function starts the Module before calling `runApp`. If startup
fails, `startupErrorBuilder` can render a fallback root; without it
the original error is rethrown. `backend` accepts an already-created
`ResolverBackend`. Use `onRuntimeCloseError` to handle
cleanup errors.

### `BetterEffectBootstrap`

Use this widget for add-to-app, previews, tests, or a subtree that needs
asynchronous startup:

```dart
BetterEffectBootstrap(
  module: appModule,
  loadingBuilder: (_) => const SplashScreen(),
  minimumLoadingDuration: const Duration(milliseconds: 250),
  errorBuilder: (context, error, stackTrace, retry) {
    return StartupError(
      error: error,
      onRetry: retry,
    );
  },
  builder: (_) => const FeatureRoot(),
)
```

The widget shows loading until the Runtime starts, exposes a retry callback
after startup failure, and closes the Runtime when it is disposed.
`backendFactory` creates a fresh resolver for every start/retry.
Change `restartKey` to intentionally restart an otherwise identical
Module. `closeRuntimeOnDetach` controls whether the Runtime also
closes when the Flutter view detaches.

### `BetterEffectProvider`

Use the provider when a Runtime already exists:

```dart
BetterEffectProvider(
  runtime: runtime,
  child: const FeatureRoot(),
)
```

The default constructor owns and closes the Runtime. Use `.value` when
another owner controls its lifecycle:

```dart
BetterEffectProvider.value(
  runtime: externallyOwnedRuntime,
  child: const FeatureRoot(),
)
```

Do not use the owning constructor for a Runtime that is also closed elsewhere.

## Flutter composition helpers

The nearest scope exposes these `BuildContext` extensions:

```dart
final commands = context.effectCommands; // non-listening
final commands = context.watchEffectCommands(); // listens for scope replacement
final runtime = context.effectRuntime;

final result = await context.runEffect(program);
final exit = await context.runEffectExit(program);
final service = context.readEffectService<ApiClient>();
```

Use `effectCommands` in ViewModel factories. Use
`watchEffectCommands()` in adapters that must recreate their object if
the Runtime scope changes. `runEffect` and
`runEffectExit` are useful at integration boundaries.
`readEffectService` is for route/provider factories and adapters;
business code should resolve services through `use<T>()` inside an
Effect.

Calling these extensions without a `BetterEffectScope` produces a
Flutter error explaining how to install one.

## Existing ViewModel base classes

If a ViewModel already extends another `ChangeNotifier` base, use
`EffectCommandOwner` instead of `EffectViewModel`:

```dart
final class HomeViewModel extends ChangeNotifier with EffectCommandOwner {
  HomeViewModel(EffectCommands commands) {
    load = ownCommand(commands(_load));
  }

  late final EffectCommand0<HomeData, AppFailure> load;

  Effect<HomeData, AppFailure> _load() => loadHome();
}
```

Owned Commands are disposed in reverse creation order when the ViewModel is
disposed.

## Observability

Pass an observer to the bootstrap, provider, or `EffectCommands`
factory to observe transitions from every Command created there:

```dart
runApp(
  BetterEffectBootstrap(
    module: appModule,
    observer: (transition) {
      debugPrint('$transition');
    },
    builder: (_) => const App(),
  ),
)
```

`EffectCommandTransition` contains the previous state, current state,
timestamp, and optional `debugLabel`. A command-specific
`stateObserver` can project a successful value into ViewModel state.
Observer failures are reported through `FlutterError`; they do not
replace the Command's typed outcome.

## Testing

Test the real Runtime → Command → ViewModel flow and replace only the services
that need to differ:

```dart
final runtime = await appModule
    .overrideWith([
      .instance<GreetingService>(FakeGreetingService()),
    ])
    .start();

final viewModel = GreetingViewModel(EffectCommands(runtime));

final exit = await viewModel.greet.execute('Dart');

expect(exit, isA<ExitSuccess<String, AppFailure>>());

viewModel.dispose();
await runtime.close();
```

For widget tests, `BetterEffectProvider.value` is convenient because
the test owns the Runtime:

```dart
await tester.pumpWidget(
  BetterEffectProvider.value(
    runtime: runtime,
    child: const MaterialApp(home: GreetingScreen()),
  ),
);
```

Remember to dispose ViewModels created directly in a test and close Runtimes that
the test owns.

## Example application

The repository includes a complete task application demonstrating:

- contextual Repository/Service resolution;
- typed failure propagation;
- initial loading and refresh;
- one-shot SnackBars;
- `drop`, `latest`, and `queue` concurrency;
- ViewModel-owned Command disposal;
- a long-lived Runtime without a global injector.

Run its tests with:

```bash
cd example
flutter pub get
flutter test
```

Generate local platform folders and run it interactively with:

```bash
flutter create . --platforms=android,ios,web,linux,macos,windows
flutter run
```

## Boundaries and limitations

- This package does not provide a second Result type; it re-exports the core API.
- It does not provide a global service locator.
- It does not replace a general state-management package.
- Arbitrary Dart Futures cannot be forcefully cancelled. Cancellation is
  ownership interruption plus an optional cooperative `onCancel` hook.
- `latest` prevents stale state updates, but older underlying work
  may continue until its Future completes.
- A Runtime should have one clear owner. Choose the owning bootstrap/provider
  constructor or `.value` for an externally owned Runtime, not both.
- Business code should normally communicate through ViewModels and Effects
  rather than resolving services directly from Widgets.

## API reference

- [API documentation](https://pub.dev/documentation/better_effect_flutter/latest/)
- [Source repository](https://github.com/nitoba/better-effect-dart)
- [Changelog](CHANGELOG.md)
- [Core package: better_effect](https://pub.dev/packages/better_effect)

## Develop this package

From the package directory:

```bash
flutter pub get
dart format .
flutter analyze --fatal-infos
flutter test
flutter pub publish --dry-run
```

The package check script also validates the example application:

```bash
./tool/check.sh
```
