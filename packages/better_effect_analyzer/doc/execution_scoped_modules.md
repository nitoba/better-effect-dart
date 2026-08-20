# Execution Module graph analysis

The project-wide graph checker recognizes statically visible `Module` values passed to:

- `Runtime.runWith`;
- `Runtime.runExitWith`;
- `Runtime.executeWith`.

These Modules are analyzed as execution overlays rather than standalone composition roots.

## Root fallback

An execution Module may request services that are not declared locally because the long-lived root Runtime can provide them.

```dart
final requestModule = Module([
  .instance<RequestContext>(RequestContext()),
  .provide<RequestRepository>(RequestRepository.new),
]);

final class RequestRepository {
  RequestRepository(this.database, this.context);

  final Database database; // may come from the root Runtime
  final RequestContext context; // provided locally
}

await runtime.runWith(requestModule, handleRequest);
```

The graph checker does not emit `missing_service` for `Database` merely because it is absent from `requestModule`.

## Diagnostics still enforced

Root fallback does not disable local structural validation. The checker still reports:

- duplicate local service identities;
- incompatible provider implementations;
- dependency cycles inside the execution Module;
- Module composition cycles;
- a local resource that depends directly or transitively on another local resource acquired later.

This remains invalid:

```dart
final requestModule = Module([
  .resource<RequestTransaction>(
    acquire: (services) {
      final database = services<LocalDatabase>();
      return RequestTransaction(database);
    },
    release: (transaction, exit) => transaction.close(exit),
  ),
  .resource<LocalDatabase>(
    acquire: (_) => LocalDatabase.open(),
    release: (database, exit) => database.close(),
  ),
]);
```

`LocalDatabase` is known to belong to the same overlay and is acquired after `RequestTransaction`, so `resource_dependency_declared_after_provider` is emitted.

## Static-analysis boundary

The checker can classify Modules when the call and Module identity are statically visible, including a named Module, an inline `Module(...)`, or a directly visible `overrideWith(...)` expression.

Highly dynamic selection may be outside this analysis boundary:

```dart
final module = chooseModuleAtRuntime(configuration);
await invokeThroughDynamicWrapper(runtime, module, effect);
```

Runtime ownership and resolution remain correct, but the graph checker may not infer that the selected value is an execution overlay. Keep execution Modules directly visible at composition boundaries when graph diagnostics are important.