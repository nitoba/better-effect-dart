# better_effect

Contextual dependency injection, typed failure propagation, and scoped resource
lifetimes for `result_dart`.

`better_effect` keeps ordinary Dart classes, `async`/`await`, constructor
tear-offs, records, patterns, and `result_dart`. It adds a lazy Effect boundary
where dependencies can be requested exactly where they are used.

```dart
import 'package:better_effect/better_effect.dart';

sealed class AppFailure implements Exception {
  const AppFailure();
}

final class UserNotFound extends AppFailure {
  const UserNotFound(this.id);

  final String id;
}

typedef AppEffect<A extends Object> = Effect<A, AppFailure>;

abstract interface class Database {
  Effect<User, AppFailure> findUser(String id);
}

abstract interface class UserRepository {
  AppEffect<User> findUser(String id);
}

final class UserRepositoryLive implements UserRepository {
  @override
  AppEffect<User> findUser(String id) => .result((use) async {
    final database = use<Database>();

    return use.unwrap(
      database.findUser(id),
    );
  });
}

final appModule = Module([
  .provide<Database>(DatabaseLive.new),
  .provide<UserRepository>(UserRepositoryLive.new),
]);
```

The repository does not receive `Database` in its constructor. The dependency
is born from this line:

```dart
final database = use<Database>();
```

The `use` value is scoped to `Effect.result`; it is not a global service
locator, a Zone, or a Module reference.

## Requirements

- Dart 3.10 or newer.
- `result_dart` 2.2.x.
- `auto_injector` 2.2.x.

## Installation

While the package is being developed locally, add it by path:

```yaml
dependencies:
  better_effect:
    path: ../better_effect
```

After the package is published on pub.dev, applications can install it with:

```bash
dart pub add better_effect
```

## Develop this package

Create a standard Dart package with:

```bash
dart create -t package better_effect
cd better_effect
```

After placing these source files in the generated project, run:

```bash
dart pub get
dart format .
dart analyze --fatal-infos
dart test
dart run example/better_effect_example.dart
```

The repository also includes `tool/check.sh`, which formats, analyzes, tests, and
runs `dart pub publish --dry-run`.

## Define an Effect

```dart
Effect<User, AppFailure> loadUser(String id) => .result((use) async {
  final users = use<UserRepository>();
  final audit = use<AuditLog>();

  final user = await use.unwrap(
    users.findUser(id),
  );

  await use.unwrap(
    audit.userLoaded(user.id),
  );

  return user;
});
```

`use.unwrap` extracts success and automatically short-circuits on failure.
The inner error type must be a subtype of the outer Effect error type.

## Interoperate with result_dart

```dart
Effect<User, AppFailure> fromExistingResult() => .result((use) async {
  final cache = use<UserCache>();

  return use.result(
    cache.readUser(),
  );
});
```

Both `ResultDart<A, E>` and `AsyncResultDart<A, E>` are accepted by
`use.result`.

A Result can also become an Effect:

```dart
final effect = result.toEffect();
final asyncEffect = asyncResult.toEffect();
```

## Fail explicitly

```dart
Effect<User, AppFailure> requireActive(User user) => .result((use) async {
  if (!user.isActive) {
    use.fail(UserInactive(user.id));
  }

  return user;
});
```

`use.fail` returns `Never`, so Dart flow analysis understands that execution
cannot continue through that branch.

## Convert exceptions into typed failures

```dart
Effect<Response, NetworkFailure> request() => .tryAsync(
  () => client.get('/users'),
  onError: NetworkFailure.from,
);
```

`Effect.tryAsync` catches `Exception`. `Effect.tryAll` is available when the
application deliberately wants to catch every thrown object, including
`Error` values.

## Configure the environment

```dart
final appModule = Module([
  .instance(const AppConfig(apiUrl: 'https://api.example.com')),
  .provide<HttpClient>(HttpClientLive.new),
  .provide<Database>(DatabaseLive.new),
  .provide<UserRepository>(UserRepositoryLive.new),
  .factory<GetUser>(GetUser.new),
]);
```

The default lifetime of `.provide` is `.lazySingleton`.

Available registration styles:

```dart
Module([
  .factory<Clock>(SystemClock.new),
  .singleton<AppBootstrap>(AppBootstrap.new),
  .lazySingleton<Database>(DatabaseLive.new),
  .instance<AppConfig>(config),
]);
```

Constructor injection remains supported because AutoInjector builds
constructor-backed services:

```dart
final class DatabaseLive implements Database {
  DatabaseLive(this._config, this._logger);

  final AppConfig _config;
  final Logger _logger;
}
```

Contextual resolution and constructor injection can coexist in the same
application.

## Run an Effect

For a short-lived program:

```dart
final result = await appModule.run(
  loadUser('user-1'),
);

result.fold(
  print,
  handleFailure,
);
```

For a long-lived application:

```dart
final runtime = await appModule.start();

try {
  final result = await runtime.run(loadUser('user-1'));
  // ...
} finally {
  await runtime.close();
}
```

Use `runExit` to preserve defects as values:

```dart
final exit = await appModule.runExit(loadUser('user-1'));

switch (exit) {
  case ExitSuccess(:final value):
    print(value);
  case ExitFailure(:final error):
    handleFailure(error);
  case ExitDefect(:final defect, :final stackTrace):
    reportDefect(defect, stackTrace);
  case ExitInterrupted():
    break;
}
```

## Replace services in tests

```dart
final testModule = appModule.overrideWith([
  .instance<Database>(FakeDatabase()),
]);
```

Or override a service for one Effect only:

```dart
final result = await appModule.run(
  loadUser('user-1').provide<Database>(FakeDatabase()),
);
```

## Named services

Use `ServiceKey<T>` only when more than one implementation of the same contract
is required:

```dart
const primaryDatabase = ServiceKey<Database>('primary');
const analyticsDatabase = ServiceKey<Database>('analytics');

final module = Module([
  .provide<Database>(
    PrimaryDatabase.new,
    key: primaryDatabase,
  ),
  .provide<Database>(
    AnalyticsDatabase.new,
    key: analyticsDatabase,
  ),
]);
```

Resolution keeps the type:

```dart
final database = use(primaryDatabase);
```

## Scoped resources

Module resources live for the entire Runtime:

```dart
final module = Module([
  .resource<Database>(
    acquire: (services) {
      final config = services<AppConfig>();
      return Database.open(config.databasePath);
    },
    release: (database) => database.close(),
  ),
]);
```

Resources are acquired in declaration order and released in reverse order.

Execution-local resources use `use.acquire`:

```dart
Effect<User, AppFailure> program() => .result((use) async {
  final connection = await use.acquire(
    openConnection(),
    release: (connection) => connection.close(),
  );

  return connection.findUser();
});
```

An execution resource is released when that `runtime.run` call ends. A Module
resource is released when the Runtime closes.

## Effect locals

Effect locals carry execution-specific values without global state or Zones:

```dart
final requestId = EffectLocal<String>(
  'unknown',
  name: 'requestId',
);

Effect<Unit, Never> logRequest() => .result((use) async {
  print(use.local(requestId));
  return unit;
});

final traced = logRequest().withLocal(
  requestId,
  'request-123',
);
```

Because `Effect` success values must extend `Object`, use the `Unit` type for
operations without a meaningful success value:

```dart
Effect<Unit, AppFailure> save() => .succeed(unit);
```

## Composition

```dart
final transformed = effect
    .map(UserView.fromDomain)
    .tap(logger.userLoaded)
    .mapError(AppFailure.fromRepository);
```

Sequential composition:

```dart
final combined = Effect.zip(loadUser(), loadPermissions());
final (user, permissions) = await use.unwrap(combined);
```

Concurrent Future composition:

```dart
final combined = Effect.parZip(loadUser(), loadPermissions());
```

`parZip` does not promise fiber cancellation. Both Dart Futures are awaited.

## Current boundary

The core package validates error compatibility through Dart generics and keeps
missing services separate from expected failures by reporting them as defects.

Compile-time validation of the complete Module graph requires an analyzer
plugin because Dart cannot derive a type-level union of every `use<T>()` call.
That plugin should live in a separate `better_effect_analyzer` package so the
runtime package stays small and does not depend on analyzer internals.
