# Execution-scoped Modules

A long-lived `Runtime` normally exposes one application environment. Some operations also need temporary providers and resources whose lifetime belongs to a single execution: request context, authentication, transactions, job metadata, feature resources, or test overrides.

Use `runWith`, `runExitWith`, or `executeWith` to install a fresh `Module` for one execution without mutating the root Runtime.

```dart
final requestModule = Module([
  .instance<RequestContext>(requestContext),
  .resource<Transaction>(
    acquire: (services) {
      final database = services<Database>();
      return database.beginTransaction();
    },
    release: (transaction, exit) => transaction.close(exit),
  ),
]);

final exit = await runtime.runExitWith(
  requestModule,
  handleRequest,
  executionLabel: 'request',
);
```

For a managed handle, use `executeWith`:

```dart
final execution = runtime.executeWith(
  requestModule,
  handleRequest,
  label: 'request',
);

execution.interrupt(reason: 'client-disconnected');
final exit = await execution.exit;
```

## Resolution rules

The execution Module is a local-first overlay:

1. A local binding shadows a root binding with the same service type and `ServiceKey`.
2. A local constructor or resource may depend on other local services.
3. Missing local services fall back to the root Runtime.
4. Root providers cannot depend on execution-local services.
5. The root backend is never mutated by an execution Module.

This allows a constructor to combine both environments:

```dart
final requestModule = Module([
  .instance<RequestContext>(requestContext),
  .provide<RequestRepository>(RequestRepository.new),
]);

final class RequestRepository {
  RequestRepository(this.database, this.context);

  final Database database; // root Runtime
  final RequestContext context; // execution Module
}
```

Named services follow the same rule:

```dart
const endpoint = ServiceKey<ApiEndpoint>('endpoint');

final requestModule = Module([
  .instance<ApiEndpoint>(previewEndpoint, key: endpoint),
]);
```

Inside this execution, `use(endpoint)` returns `previewEndpoint`; outside it, the root value remains unchanged.

## Resource ownership

Execution Module resources are acquired into the managed execution Scope. Cleanup order is:

1. resources acquired by the user Effect;
2. execution Module resources, in reverse acquisition order;
3. constructor-backed overlay services;
4. root Runtime resources only when the root Runtime closes.

A logical timeout or interruption does not release resources still used by physical work. The Runtime keeps the execution Scope alive until the underlying Future and all cleanup complete.

Partial Module startup is also scoped. If a later local resource fails to acquire, resources already acquired for that execution are released with the resulting defect before the execution completes.

## Reuse and concurrency

`Module` remains an immutable description. The same value may be reused across executions:

```dart
final first = runtime.executeWith(requestModule, firstRequest);
final second = runtime.executeWith(requestModule, secondRequest);
```

Each call receives an isolated overlay, separate service instances, and a separate execution Scope.

## Custom resolver backends

Normal `ResolverBackend` implementations continue to support regular Runtime execution. To support execution-scoped Modules, implement `ResolverBackendOverlayFactory`:

```dart
final class CustomBackend
    implements ResolverBackend, ResolverBackendOverlayFactory {
  @override
  ResolverBackend createExecutionOverlay() {
    return CustomBackend.child(parent: this);
  }
}
```

The returned backend must:

- keep local registrations isolated;
- resolve local services before falling back to the parent;
- close only overlay-owned state;
- never close or mutate the parent backend.

`AutoInjectorBackend` provides this capability by default. Calling `runWith`, `runExitWith`, or `executeWith` on a backend without it produces `ResolverBackendOverlayUnsupportedException` as an execution defect.