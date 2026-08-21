# Child Runtime Modules

The graph checker distinguishes feature-length child Runtime Modules from application composition roots and one-execution overlays.

A Module is classified as a child Runtime environment when it is statically visible in:

```dart
final feature = await runtime.fork(
  checkoutModule,
  label: 'checkout',
);
```

or in a Flutter feature boundary:

```dart
BetterEffectFeatureScope(
  module: checkoutModule,
  builder: (_) => const CheckoutFlow(),
)
```

The public graph projection exposes this through:

```dart
module.isChildRuntimeModule
```

## Validation semantics

A child Runtime Module is not inferred as an application root. Its unresolved requirements may be supplied by the parent Runtime.

The analyzer still validates defects that are local to the child environment:

- duplicate bindings;
- incompatible implementations;
- dependency cycles;
- Module composition cycles;
- local resource startup ordering.

Graph explanation APIs therefore keep parent requirements in `externalRequirements` when the parent composition cannot be proven statically.

## Manual ownership

A manually forked Runtime is an owned lifecycle value. The existing `runtime_started_without_close` warning applies to unowned `Runtime.fork` results:

```dart
final feature = await runtime.fork(featureModule); // warning if it escapes no owner
```

Use a visible owner or a `try/finally` boundary:

```dart
final feature = await runtime.fork(featureModule);
try {
  await feature.run(program);
} finally {
  await feature.close();
}
```

## Dynamic limitations

Static analysis deliberately does not invent a parent environment when the parent Runtime is chosen through dynamic control flow, navigation state, runtime configuration, or another opaque factory.

In those cases child requirements remain external. Cover the complete composition with integration tests and Runtime-level tests.
