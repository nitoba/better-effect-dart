# Command selectors and rebuild filtering

`EffectCommandBuilder` remains the simplest way to render the complete
typed state. Use selectors when only a small fragment depends on one
projection such as loading, visible data, the current failure, or queue
depth.

## Select from state

```dart
EffectCommandSelector<User, AppFailure, bool>(
  command: viewModel.loadUser,
  selector: (state) => state.isRunning,
  child: const UserContent(),
  builder: (context, running, child) {
    return LoadingOverlay(visible: running, child: child!);
  },
)
```

Selection is synchronous and read-only. The selector receives an
immutable `EffectCommandState` and cannot execute, reset, or mutate the
Command through that value.

## Equality

Dart `==` is the default. This is appropriate for bools, records,
enums, immutable value objects, and nullable scalar values.

For collections, supply explicit equality:

```dart
EffectCommandSelector<List<User>, AppFailure, List<User>?>(
  command: viewModel.loadUsers,
  selector: (state) => state.dataOrNull,
  equals: (previous, current) => listEquals(previous, current),
  builder: ...,
)
```

The equality callback affects only widget rebuilding. It does not hide
state from listeners or change Command history.

## Select coordination metadata

Queue and debounce/throttle counts can change without creating a new UI
state revision. Select them from the read-only snapshot:

```dart
EffectCommandSelector.snapshot(
  command: viewModel.save,
  selector: (snapshot) => (
    pending: snapshot.pendingCount,
    queued: snapshot.queuedCount,
    trigger: snapshot.triggerPendingCount,
  ),
  builder: (context, counts, child) => QueueStatus(counts: counts),
)
```

A snapshot also exposes `state`, `lastExit`, `policy`, `isRunning`,
`dataOrNull`, `errorOrNull`, and `isTerminal`.

## Filter the full-state builder

```dart
EffectCommandBuilder<User, AppFailure>(
  command: viewModel.loadUser,
  buildWhen: (previous, current) {
    return previous.dataOrNull != current.dataOrNull;
  },
  builder: (context, state, child) => UserContent(
    user: state.dataOrNull,
  ),
)
```

`buildWhen` compares every consecutive Command transition. When it
returns false, the subtree keeps rendering the last accepted state, but
the rejected state becomes the next comparison baseline.

## Command replacement and child reuse

Selector and builder widgets detach the old Command and attach the new
one in `didUpdateWidget`. The new Command's current value is rendered
immediately. A supplied `child` is passed through unchanged, matching
Flutter's standard builder conventions.

## One-shot listeners remain independent

`EffectCommandListener` continues to consume state revisions for
navigation, dialogs, SnackBars, and analytics. Snapshot-only changes do
not create revisions and cannot repeat those effects. A selector and
listener can safely wrap the same Command.

## Isolate small subtrees

Prefer selectors around the smallest meaningful fragment:

```dart
Stack(
  children: [
    const UserContent(),
    EffectCommandSelector<User, AppFailure, bool>(
      command: viewModel.loadUser,
      selector: (state) => state.isRunning,
      builder: (context, running, child) {
        return IgnorePointer(
          ignoring: !running,
          child: Opacity(
            opacity: running ? 1 : 0,
            child: const LoadingOverlay(),
          ),
        );
      },
    ),
  ],
)
```

This is a rendering optimization, not a replacement for application
state management or arbitrary computed signals.
