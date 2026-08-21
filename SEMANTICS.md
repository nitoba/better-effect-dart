# better_effect normative semantics

Status: **Normative** for the stable behavior of `better_effect` and
`better_effect_flutter` in this repository.

This document defines compatibility semantics, not implementation structure.
Private types, scheduling mechanisms, resolver internals, and data structures may
change freely while these rules remain true.

Requirement words are deliberate:

- **MUST** / **MUST NOT** define compatibility requirements.
- **SHOULD** / **SHOULD NOT** define defaults that should change only for a
  documented reason.
- **MAY** describes behavior callers cannot rely on.

Every stable **MUST** / **MUST NOT** rule below has a stable rule ID and an
executable scenario in `packages/better_effect_conformance`. Repository-process
requirements are described separately in the semantic migration policy.

## 1. Effect and Exit

### Construction and execution

- `EFFECT-01` — Effect construction **MUST** be lazy. Creating, mapping,
  composing, retrying, timing out, or labelling an Effect **MUST NOT** execute
  its body before an execution boundary runs the resulting program.
- `EFFECT-02` — Expected failures raised through the typed failure channel
  **MUST** remain typed failures unless an explicit recovery/composition
  operator transforms them.
- `EFFECT-03` — Unexpected throws that are not part of the typed failure channel
  **MUST** be represented as defects at `Exit` boundaries and **MUST NOT** be
  silently converted into domain failures.
- `EFFECT-04` — `run` **MUST** expose success/typed-failure through
  `ResultDart`, while `runExit` **MUST** preserve all logical outcomes: success,
  typed failure, defect, and interruption.
- `EFFECT-05` — Once logical interruption is published for a caller, that
  interruption **MUST** remain authoritative for that caller even if
  non-cooperative physical work continues. The Runtime **MUST** keep owning the
  physical work and cleanup until they actually finish.

## 2. Outcome and cleanup precedence

Cleanup is part of the execution model. Work outcome and cleanup outcome combine
according to this matrix:

| Rule | Work outcome | Cleanup | Required meaning |
| --- | --- | --- | --- |
| `OUTCOME-01` | success | success | **MUST** remain success |
| `OUTCOME-02` | success | failure | **MUST** become a defect representing cleanup failure |
| `OUTCOME-03` | typed failure | success | **MUST** remain that typed failure |
| `OUTCOME-04` | typed failure | failure | **MUST** keep the typed failure authoritative and surface cleanup diagnostics separately |
| `OUTCOME-05` | defect | success | **MUST** preserve the original defect |
| `OUTCOME-06` | defect | failure | **MUST** preserve both defects without replacing the primary defect |
| `OUTCOME-07` | interruption | success | **MUST** remain interruption |
| `OUTCOME-08` | interruption | failure | **MUST** keep interruption authoritative and surface cleanup diagnostics separately |

- `OUTCOME-09` — Runtime observer callbacks that throw **MUST NOT** replace,
  mutate, or reinterpret an Effect outcome. Observer failures **MUST** remain
  isolated in the observer-error channel.

## 3. Scope and resources

- `SCOPE-01` — Scope ownership **MUST** form a tree. Closing a Scope **MUST**
  close child Scopes before that Scope's own finalizers. Sibling children and
  finalizers **MUST** close in reverse creation/registration order (LIFO).
- `SCOPE-02` — Resource acquisition **MUST** be atomic with finalizer ownership.
  If acquisition finishes after close has begun, the acquired value **MUST** be
  released exactly once and **MUST NOT** escape as a live owned resource.
- `SCOPE-03` — Release/finalizer callbacks **MUST** receive the logical `Exit`
  that closes their Scope.
- `SCOPE-04` — Multiple cleanup failures **MUST** be aggregated in deterministic
  cleanup order rather than stopping at the first cleanup failure.
- `SCOPE-05` — `Scope.close` **MUST** be idempotent. Concurrent or repeated
  closes **MUST** share the same close operation and finalizers **MUST** execute
  once.
- `SCOPE-06` — Once a Scope is closing or closed, it **MUST NOT** accept a new
  child Scope, finalizer, or acquisition as newly owned work.

## 4. Runtime lifecycle and environments

### Runtime state and managed execution

- `RUNTIME-01` — A Runtime transitions `active -> closing -> closed`. Once close
  starts it **MUST NOT** admit new executions or public service-resolution
  boundaries.
- `RUNTIME-02` — Graceful shutdown with interruption enabled **MUST** request
  cooperative cancellation after the configured grace boundary and **MUST**
  wait for physically owned executions before releasing Runtime resources.
- `RUNTIME-03` — Cancellation **MUST NOT** pretend to force-cancel arbitrary Dart
  Futures. Non-cooperative work **MUST** stay physically owned until it really
  finishes.
- `RUNTIME-04` — An execution admitted while its Runtime was active **MUST** keep
  resolving the environment it owns even if the Runtime enters `closing` while
  that execution is in flight.
- `RUNTIME-05` — Timeout may publish a logical typed failure before the source
  Future finishes, but any resource acquired late by that source **MUST** remain
  owned and **MUST** be cleaned before physical completion/Runtime release.

### Root, child, and execution environments

Resolution precedence is:

```text
execution-scoped Module
        ↓
child Runtime
        ↓
parent/root Runtime
```

- `ENV-01` — An execution-scoped Module **MUST** resolve its local bindings first
  and **MUST** fall back to its owning Runtime without mutating parent
  registrations.
- `ENV-02` — A child Runtime **MUST** resolve child bindings first and **MUST**
  fall back to its parent. Closing a child **MUST NOT** close the parent.
- `ENV-03` — Parent shutdown **MUST** coordinate and close active child Runtimes
  before releasing parent-owned resources.

## 5. Concurrency and retry

### Collection concurrency

- `CONCURRENCY-01` — Positive bounded concurrency **MUST NOT** run more than the
  requested maximum number of child operations at once.
- `CONCURRENCY-02` — Collection result order **MUST** match input order regardless
  of physical completion order.
- `CONCURRENCY-03` — When several already-started children fail or defect,
  selected typed failure or defect **MUST** be deterministic by the lowest
  started input index, not by timing race.
- `CONCURRENCY-04` — After a typed failure or defect is observed, no new child
  work **MUST** be scheduled; already-started work **MUST** remain physically
  owned until completion and cleanup.
- `CONCURRENCY-05` — After owner interruption, no new child work **MUST** be
  scheduled; already-started work **MUST** remain physically owned until
  completion and cleanup.

### Retry

- `RETRY-01` — Retry policies **MUST** retry typed failures according to
  `maxAttempts`; `maxAttempts` counts the initial attempt.
- `RETRY-02` — Defects **MUST NOT** be retried by the typed-failure retry policy.
- `RETRY-03` — Every retry attempt **MUST** own a child Scope, and that Scope
  **MUST** close before retry-policy evaluation/delay or before the next attempt
  starts.
- `RETRY-04` — Interruption or attempt-cleanup failure **MUST** stop retry
  scheduling immediately.

## 6. Flutter EffectCommand semantics

Command policy decides visible-state authority. It does not erase an accepted
caller's individual completion.

- `COMMAND-01` — Visible Command state **MUST** distinguish idle, running,
  success, typed failure, defect, and interruption without inventing domain
  failures for cancellation/policy decisions.
- `COMMAND-02` — Every accepted caller **MUST** receive the `Exit` of the work it
  owns, even when another execution has newer visible-state authority.
- `COMMAND-03` — `drop` **MUST** keep one active execution and **MUST NOT** start
  duplicate work for dropped calls.
- `COMMAND-04` — `latest` **MUST** make the newest accepted call authoritative for
  visible state; stale completions **MUST NOT** replace newer state. With
  `cancelPrevious: true`, replaced active work **MUST** receive cooperative
  interruption.
- `COMMAND-05` — `queue` **MUST** start accepted callers in request order and
  **MUST NOT** start queued work before the active physical slot becomes
  available.
- `COMMAND-06` — Clearing/disposal of queued work **MUST** complete queued callers
  that never started as `ExitInterrupted` and **MUST NOT** start them later.
- `COMMAND-07` — Existing `EffectCommandConcurrency.drop/latest/queue` values
  **MUST** translate to behavior equivalent to their `CommandPolicy`
  counterparts.
- `COMMAND-08` — `EffectCommandListener` one-shot delivery **MUST NOT** deliver
  the same visible state revision more than once.
- `COMMAND-09` — Command cancel/dispose may publish interruption immediately,
  but Runtime resource ownership **MUST** continue until physical execution and
  cleanup finish.
- `COMMAND-10` — Debounce/throttle timing **MUST** use the Runtime-owned
  `EffectClock`; superseded pending callers **MUST** complete deterministically
  without depending on host wall-clock sleeps.

## 7. Flutter Runtime ownership

- `OWNERSHIP-01` — `BetterEffectProvider.value` / external ownership **MUST NOT**
  close the supplied Runtime when the widget leaves the tree.
- `OWNERSHIP-02` — A widget/application boundary that declares Runtime ownership
  **MUST** close that Runtime exactly once according to its lifecycle policy.
- `OWNERSHIP-03` — `BetterEffectBootstrap` **MUST** close a stale Runtime whose
  asynchronous startup completes after the owning generation was disposed or
  restarted.
- `OWNERSHIP-04` — `BetterEffectFeatureScope` **MUST** own and close only its
  child Runtime; disposal/restart **MUST NOT** close the parent Runtime.

## 8. Deterministic conformance

Conformance scenarios avoid arbitrary wall-clock sleeps and runner-speed
assumptions. Race-sensitive scenarios use explicit gates/signals,
`ManualEffectClock`, Runtime events, or Flutter's fake clock. Scenarios assert
public behavior specified here rather than private implementation layout.

The rule catalog in `packages/better_effect_conformance/lib/conformance.dart`
and the scenario registry are checked by a meta-test so documented stable rule
IDs and executable scenarios stay synchronized.

## 9. Semantic alignment with TypeScript `better-effect`

Dart and TypeScript intentionally share a model, not an implementation. Shared
names should avoid contradictory ownership/outcome meaning.

| Semantic area | Dart | TypeScript | Compatibility expectation |
| --- | --- | --- | --- |
| Effect laziness | Effect bodies run only at an execution boundary | `Effect.fn` creates lazy Programs; contextual `Effect.gen` may execute immediately | User-visible Program values **SHOULD** remain lazy; eager contextual helpers are language-specific |
| Typed failure | `result_dart` failure channel | `better-result` failure channel | Expected failures **SHOULD** stay typed and separate from thrown defects |
| Runtime dependency access | `EffectContext` + Module/Runtime | Runtime + Layer/Context | Child/local environments **SHOULD** shadow parent services without mutating parents |
| Resource lifetime | Scope tree + Runtime-owned resources | Scope/Layer-owned resources | Resources **SHOULD** release according to lexical/owner lifetime; child cleanup precedes parent cleanup |
| Interruption | Cooperative `CancellationSignal`; physical ownership retained | Cooperative `AbortSignal`; arbitrary work is not force-killed | Interruption **SHOULD** be cooperative and **SHOULD NOT** imply arbitrary Future/Promise cancellation |
| Execution overlays | `runWith` / `runExitWith` / `executeWith` | `runWith` execution Layer | Temporary environments **SHOULD** be execution-owned and released after physical completion |
| Persistent child Runtime | First-class `Runtime.fork` and Flutter feature scope | No equivalent contract required today | Dart-specific feature; TypeScript parity is a possible future extension, not a current requirement |
| Flutter Commands | First-class Flutter adapter | No equivalent UI adapter | Dart/Flutter-specific; no TypeScript parity requirement |

A cross-language semantic change should update this table when a shared concept
would otherwise acquire contradictory ownership or outcome meaning.

## 10. Semantic migration policy

Changing a stable rule above is a compatibility change even if no public Dart
signature changes. Repository policy requires the same change set to:

1. update the affected rule in this document;
2. update/add the corresponding conformance scenario;
3. add an entry to every affected package `CHANGELOG.md`;
4. add a migration entry to [`docs/semantic-migrations.md`](docs/semantic-migrations.md)
   describing old behavior, new behavior, impact, and migration;
5. document whether the change also affects TypeScript semantic alignment.

A refactor that preserves all stable rules does not require a semantic migration
entry.
