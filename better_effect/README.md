# better_effect

[![pub package](https://img.shields.io/pub/v/better_effect.svg)](https://pub.dev/packages/better_effect)
[![Dart SDK](https://img.shields.io/badge/Dart-%E2%89%A53.10.0-0175C2.svg)](https://dart.dev/)

Typed Effects for Dart: contextual dependency injection, typed failures, and
scoped resource lifetimes without global state.

`better_effect` is a small runtime for describing application operations as
lazy values. An `Effect<A, E>` can produce a value of type `A` or an expected
failure of type `E`. While the Effect is running, its body can request services
from the current runtime, compose other Effects, use `result_dart`, and acquire
resources that are released automatically.

It is Dart-only and has no Flutter dependency.

## Why use it?

`better_effect` is useful when an application needs all of the following:

- dependencies that are explicit in the runtime environment but can be
  requested at the point where they are used;
- expected failures represented by types instead of exceptions;
- a clear distinction between expected failures and programming/runtime
  defects;
- deterministic setup and cleanup for databases, clients, subscriptions, and
  other resources;
- test-time replacement of services without a global service locator;
- ordinary Dart code with `async`/`await`, records, pattern matching, and
  constructor injection.

It does not try to be a state-management package, an application framework, or
a replacement for every dependency-injection library. It provides the Effect,
Module, and Runtime primitives that can sit underneath those choices.

## The mental model

There are four parts:

| Part | Responsibility |
| --- | --- |
| `Effect<A, E>` | A lazy operation that succeeds with `A` or fails with `E`. |
| `EffectContext<E>` | The read-only `use` value available inside an Effect body. |
| `Module` | A declaration of services, lifetimes, instances, and resources. |
| `Runtime` | The live environment that starts the Module, runs Effects, and closes resources. |

An Effect does not execute when it is constructed. A Module is also a
description: constructor-backed services and resources are not evaluated until
the Module is started or used to run an Effect.

```text
Module (declarations)
        │ start / run
        ▼
Runtime (services + scopes)
        │ run
        ▼
Effect<A, E>
        │
        ├── success: A
        ├── expected failure: E
        └── defect: unexpected exception, Error, or resolution/cleanup failure
```

The default `Module.run` API returns a `ResultDart<A, E>` for the first two
outcomes and rethrows defects. Use `runExit` when the defect must be inspected
as a value as well.

## Requirements

- Dart 3.10 or newer;
- [`result_dart`](https://pub.dev/packages/result_dart) 2.2.x;
- [`auto_injector`](https://pub.dev/packages/auto_injector) 2.2.x.

## Installation

Add the package to a Dart application or package:

```bash
dart pub add better_effect
```

Or add it manually:

```yaml
dependencies:
  better_effect: ^0.1.0
```

During local monorepo development, a path dependency can be used instead:

```yaml
dependencies:
  better_effect:
    path: ../better_effect
```

## A complete example

This is the smallest complete flow: declare an Effect, request a service from
the context, map an exception into an application failure, and run it through
a Module.

```dart
import 'package:better_effect/better_effect.dart';

typedef AppEffect<A extends Object> = Effect<A, AppFailure>;

sealed class AppFailure implements Exception {
  const AppFailure();
}

final class GreetingUnavailable extends AppFailure {
  const GreetingUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'Greeting unavailable: $reason';
}

abstract interface class GreetingService {
  AppEffect<String> greet(String name);
}

final class GreetingServiceLive implements GreetingService {
  @override
  AppEffect<String> greet(String name) => Effect.tryAsync(
        () async => 'Hello, $name!',
        onError: (error, stackTrace) =>
            GreetingUnavailable(error.toString()),
      );
}

final appModule = Module([
  .provide<GreetingService>(GreetingServiceLive.new),
]);

AppEffect<String> greet(String name) => Effect.result((use) async {
      final service = use<GreetingService>();
      return use.unwrap(service.greet(name));
    });

Future<void> main() async {
  final result = await appModule.run(greet('Dart'));

  result.fold(
    (value) => print(value),
    (failure) => print(failure),
  );
}
```

The dependency is not a global lookup. `use<GreetingService>()` resolves from
the Runtime that is executing this particular Effect. The same Effect can be
run with a different Module or with a test override.

## Define Effects

### Use ordinary `async`/`await`

`Effect.result` is the main constructor for application code. The body receives
an `EffectContext<E>`; by convention it is named `use`.

```dart
Effect<User, AppFailure> loadUser(String id) =>
    Effect.result((use) async {
      final users = use<UserRepository>();
      final audit = use<AuditLog>();

      final user = await use.unwrap(users.findUser(id));
      await use.unwrap(audit.userLoaded(user.id));

      return user;
    });
```

The context is read-only. It can resolve services, compose Results and Effects,
fail with a typed error, read locals, and acquire scoped resources. It cannot
mutate the Module or the dependency-injection backend.

### Propagate typed failures

`use.unwrap` runs another Effect and returns its success value. If the nested
Effect returns an expected failure, the current body stops immediately and the
failure is propagated. The nested error type must be compatible with the outer
Effect error type.

`use.result` does the same for a synchronous or asynchronous
`ResultDart<A, E>`:

```dart
Effect<User, AppFailure> readCachedUser() =>
    Effect.result((use) async {
      final cache = use<UserCache>();

      return use.result(cache.readUser());
    });
```

Fail explicitly with `use.fail` when a branch represents an expected domain
failure:

```dart
Effect<User, AppFailure> requireActive(User user) =>
    Effect.result((use) async {
      if (!user.isActive) {
        use.fail(UserInactive(user.id));
      }

      return user;
    });
```

`use.fail` returns `Never`, so Dart flow analysis understands that the branch
does not continue.

### Choose an exception boundary deliberately

Use `Effect.tryAsync` when an operation can throw an `Exception` that belongs
in the typed failure channel:

```dart
Effect<Response, NetworkFailure> request() => Effect.tryAsync(
      () => client.get('/users'),
      onError: (error, stackTrace) =>
          NetworkFailure.from(error, stackTrace),
    );
```

`tryAsync` catches objects that implement `Exception`. Dart `Error` values and
other thrown objects remain defects. Use `Effect.tryAll` only when the
application intentionally wants to map every thrown object, including `Error`,
into a typed failure.

`Effect.sync` is useful for lazy synchronous work. Exceptions from `sync` are
defects; they are not silently converted into expected failures.

### Construct Effects directly

The other constructors cover common boundaries:

| Constructor | Use it for |
| --- | --- |
| `Effect.succeed(value)` | An already-known successful value. |
| `Effect.fail(error)` | An already-known expected failure. |
| `Effect.sync(operation)` | Lazy synchronous work. |
| `Effect.fromResult(operation)` | A lazy `ResultDart`-producing operation. |
| `Effect.defer(operation)` | Delaying construction of another Effect until execution. |
| `Effect.tryAsync(operation, onError: ...)` | Mapping thrown `Exception` values. |
| `Effect.tryAll(operation, onError: ...)` | Mapping every thrown object. |
| `Effect.service<T>()` | Describing a service lookup as an Effect. |

## Configure services with a Module

```dart
final appModule = Module([
  .instance(const AppConfig(apiUrl: 'https://api.example.com')),
  .provide<HttpClient>(HttpClientLive.new),
  .provide<Database>(DatabaseLive.new),
  .provide<UserRepository>(UserRepositoryLive.new),
  .factory<GetUser>(GetUser.new),
]);
```

Constructor-backed services can use ordinary constructor injection. The
default AutoInjector backend resolves constructor parameters for you:

```dart
final class UserRepositoryLive implements UserRepository {
  UserRepositoryLive(this._database, this._logger);

  final Database _database;
  final Logger _logger;
}
```

Contextual resolution and constructor injection are complementary. Use
constructor injection for stable structural dependencies and `use<T>()` for
dependencies that are needed by a particular operation.

### Binding lifetimes

| Binding | Behavior |
| --- | --- |
| `.factory<T>(Constructor.new)` | A new instance on every resolution. |
| `.singleton<T>(Constructor.new)` | Create eagerly when the Runtime starts, then reuse it. |
| `.lazySingleton<T>(Constructor.new)` | Create on first resolution, then reuse it. |
| `.provide<T>(Constructor.new)` | Shorthand for a constructor binding; its default lifetime is `lazySingleton`. |
| `.instance<T>(value)` | Use an already-created value. |
| `.resource<T>(acquire: ..., release: ...)` | Acquire an owned resource at Runtime startup and release it during Runtime shutdown. |

Resources are acquired in declaration order and released in reverse order. A
resource's `acquire` callback receives `Services`, a read-only service view for
composition boundaries:

```dart
final appModule = Module([
  .instance(const AppConfig(apiUrl: 'https://api.example.com')),
  .resource<DatabaseConnection>(
    acquire: (services) async {
      final config = services<AppConfig>();
      return DatabaseConnection.connect(config.apiUrl);
    },
    release: (connection) => connection.close(),
  ),
]);
```

When a resource is tied to one Effect execution rather than the whole Runtime,
use `use.acquire`:

```dart
final effect = Effect<String, AppFailure>.result((use) async {
  final connection = await use.acquire(
    Effect.tryAsync(
      () => DatabaseConnection.open(),
      onError: (error, stackTrace) =>
          DatabaseFailure.from(error, stackTrace),
    ),
    release: (connection) => connection.close(),
  );

  return connection.queryGreeting();
});
```

The release callback runs when the execution scope closes, even when the Effect
fails. Release failures are represented as defects.

### Named services with `ServiceKey`

The service type is normally enough to identify a registration. Use a typed key
when multiple implementations share the same contract:

```dart
abstract interface class Endpoint {
  Uri get uri;
}

const primaryEndpoint = ServiceKey<Endpoint>('primary');
const analyticsEndpoint = ServiceKey<Endpoint>('analytics');

final module = Module([
  .instance<Endpoint>(PrimaryEndpoint(), key: primaryEndpoint),
  .instance<Endpoint>(AnalyticsEndpoint(), key: analyticsEndpoint),
]);

final effect = Effect<(Uri, Uri), Never>.result((use) async {
  final primary = use(primaryEndpoint).uri;
  final analytics = use(analyticsEndpoint).uri;
  return (primary, analytics);
});
```

Keys are part of the registration identity. A type can therefore have one
unnamed registration plus any number of differently named registrations.

### Compose and override Modules

Modules are immutable descriptions. Combine feature Modules with
`Module.merge`, and replace matching registrations with `overrideWith`:

```dart
final coreModule = Module([
  .provide<Clock>(SystemClock.new),
]);

final userModule = Module([
  .provide<UserRepository>(UserRepositoryLive.new),
]);

final appModule = Module.merge([coreModule, userModule]);

final testModule = appModule.overrideWith([
  .instance<Clock>(FakeClock.fixed(DateTime(2026, 1, 1))),
]);
```

`overrideWith` replaces bindings with the same service type and key. Duplicate
bindings in a Module are rejected immediately with
`DuplicateServiceBindingException`.

## Compose Effects

Every `Effect<A, E>` has the following operators:

| Operator | Behavior |
| --- | --- |
| `.map(...)` | Transform a successful value. |
| `.flatMap(...)` | Continue with another Effect after success. |
| `.mapError(...)` | Transform the typed failure. |
| `.catchAll(...)` | Recover every typed failure with another Effect. |
| `.tap(...)` | Observe a success without changing it. |
| `.tapError(...)` | Observe a typed failure without changing it. |
| `.asUnit()` | Discard the success value and return `Unit`. |
| `.provide(value)` | Override one service for this Effect only. |
| `.withLocal(local, value)` | Override one `EffectLocal` for this Effect only. |
| `.timeout(duration, onTimeout: ...)` | Return a typed timeout failure if the Effect does not finish in time. |
| `.either()` | Move the typed failure into a successful `ResultDart` value. |

Use `Effect.zip` for sequential composition that returns a Dart record:

```dart
final dashboard = Effect.zip(
  loadProfile(),
  loadNotifications(),
);

final result = await appModule.run(dashboard);
final (profile, notifications) = result.getOrThrow();
```

Use `Effect.parZip` to start two Effects concurrently:

```dart
final dashboard = Effect.parZip(
  loadProfile(),
  loadNotifications(),
);
```

Both Effects must use the same typed error type. `parZip` waits for both
underlying Futures before returning; Dart Futures do not provide general
fiber-style cancellation.

The `timeout` operator has the same Dart Future limitation: it returns the
timeout result, but it cannot cancel work already running underneath.

### Interoperate with `result_dart`

The package re-exports `result_dart` and provides conversions in both
directions:

```dart
final Effect<User, UserFailure> fromResult = existingResult.toEffect();
final Effect<User, UserFailure> fromAsyncResult = existingAsyncResult.toEffect();
final ResultDart<User, UserFailure> asResult = await appModule.run(fromResult);
```

Inside an Effect body, prefer `use.result(...)` when the Result is part of a
larger operation so that its failure is propagated automatically.

## Run Effects

### One-shot execution

`Module.run` starts a Runtime, executes one Effect, releases execution and
module resources, and closes the Runtime before returning:

```dart
final result = await appModule.run(loadUser('user-1'));

result.fold(
  (user) => print('Loaded: $user'),
  (failure) => print('Expected failure: $failure'),
);
```

The returned `ResultDart` contains successful values and expected typed
failures. Unexpected defects are thrown with their original stack trace.

### Long-lived execution

Start a Runtime once when an application or feature starts, reuse it, and close
it during shutdown:

```dart
final runtime = await appModule.start();

try {
  final first = await runtime.run(loadUser('user-1'));
  final second = await runtime.run(loadUser('user-2'));
  // Handle first and second results.
} finally {
  await runtime.close();
}
```

`runtime.services` exposes a read-only `Services` view for boundaries such as
bootstrap code, resource composition, or integration adapters:

```dart
final logger = runtime.services<Logger>();
```

Calling `run` or resolving services after `runtime.close()` raises
`RuntimeClosedException`.

### Preserve defects with `runExit`

Use `runExit` when infrastructure code needs to distinguish every outcome:

```dart
final exit = await appModule.runExit(loadUser('user-1'));

switch (exit) {
  case ExitSuccess(value: final user):
    print('Loaded: $user');
  case ExitFailure(error: final failure):
    print('Expected failure: $failure');
  case ExitDefect(defect: final error, stackTrace: final stackTrace):
    reportDefect(error, stackTrace);
  case ExitInterrupted():
    print('Execution was interrupted.');
}
```

`ExitDefect` can contain an exception, a Dart `Error`, a missing dependency, or
a cleanup failure. `ExitInterrupted` is used when a Runtime is closed without a
successful or expected-failure result.

## Per-execution context with `EffectLocal`

`EffectLocal<T>` is a typed value inherited by nested Effects. It is useful for
request IDs, tracing metadata, feature flags, or authentication context that
should vary per execution without globals or Zones.

```dart
const requestId = EffectLocal<String>('unknown', name: 'requestId');

final logRequest = Effect<Unit, Never>.result((use) async {
  print('request=${use.local(requestId)}');
  return unit;
});

await appModule.run(
  logRequest.withLocal(requestId, 'request-123'),
);
```

For a one-off service replacement, use `.provide` on the Effect instead:

```dart
final testRequest = loadUser('user-1').provide<UserRepository>(fakeRepository);
```

The override is limited to that Effect and the Effects it composes.

## Testing

The recommended testing pattern is to keep production Modules and replace
only the services a test needs:

```dart
final production = Module([
  .provide<Clock>(SystemClock.new),
  .provide<UserRepository>(UserRepositoryLive.new),
]);

final testModule = production.overrideWith([
  .instance<Clock>(FakeClock.fixed(DateTime(2026, 1, 1))),
  .instance<UserRepository>(FakeUserRepository()),
]);

final result = await testModule.run(loadUser('user-1'));
```

For a single test case, `.provide` is often more focused:

```dart
final result = await production.run(
  loadUser('user-1').provide<UserRepository>(FakeUserRepository()),
);
```

Each `Module.run` call owns and closes its Runtime, so tests do not need to
manually clean up module resources.

## Design boundaries and operational details

- **Effects are lazy.** Constructing an Effect does not call its operation or
  resolve services.
- **Expected failures are typed.** Use `E` for failures the application can
  anticipate and handle.
- **Defects remain visible.** Unexpected exceptions, `Error` values, missing
  services, duplicate bindings, and cleanup failures are not silently turned
  into domain failures.
- **Scopes are deterministic.** Runtime resources are released in reverse
  acquisition order; `use.acquire` resources are released when their execution
  ends.
- **There is no general cancellation.** `parZip` and `timeout` use Dart
  Futures, so already-running work may continue in the background.
- **The default backend is AutoInjector.** Advanced applications can provide a
  custom `ResolverBackend` to `Module.start`, `Module.run`, or `Module.runExit`.
- **Runtime services are scoped.** A service belongs to a Runtime; the package
  does not create a process-wide service locator.

## API reference

- [API documentation](https://pub.dev/documentation/better_effect/latest/)
- [Source repository](https://github.com/nitoba/better-effect-dart)
- [Changelog](CHANGELOG.md)

The package exports the public `better_effect` API from one import:

```dart
import 'package:better_effect/better_effect.dart';
```

It also re-exports the public `result_dart` types used by Effect results.

## Develop this package

From the package directory:

```bash
dart pub get
dart format .
dart analyze --fatal-infos
dart test
dart run example/better_effect_example.dart
```

The repository check script runs the formatting, analysis, tests, and a
publication dry run:

```bash
./tool/check.sh
```
