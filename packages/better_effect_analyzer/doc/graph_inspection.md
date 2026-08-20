# Inspecting the dependency graph

The analyzer can export the same dependency graph it uses for Module
validation. This is useful when reviewing a composition root, explaining why
a service is present, generating an architecture diagram, or publishing
diagnostics to CI systems.

## Export the graph

```bash
dart run better_effect_analyzer --graph
dart run better_effect_analyzer --graph --format json
dart run better_effect_analyzer --graph --format dot > graph.dot
dart run better_effect_analyzer --graph --format mermaid > graph.mmd
```

The JSON document includes a `schemaVersion`, stable entity IDs, source
locations relative to the analyzed package, explicit and inferred roots,
execution overlays, effective providers after composition and overrides,
service keys, lifetimes, diagnostics, and dependency edges.

A consumer can negotiate the serialized contract without analyzing a project:

```bash
dart run better_effect_analyzer --schema-version
```

A consumer must reject a schema major version greater than the one it
understands. Additive fields can be ignored when the major version is supported.

## Explain a Module

```bash
dart run better_effect_analyzer --explain appModule
dart run better_effect_analyzer --explain appModule --format json
```

The explanation shows the effective providers visible from that environment,
including providers inherited through composition and the dependencies each
one requests. Execution-scoped Modules also show requirements expected to fall
back to the root Runtime.

A name must identify exactly one Module. For duplicate names, use the stable
Module ID shown by `--graph`.

## Explain why a service is required

```bash
dart run better_effect_analyzer --why Database
dart run better_effect_analyzer --why Database --module appModule
```

Paths are reported from entry-provider candidates toward the requested
service, for example:

```text
appModule: UserController -> UserRepository -> Database
```

When a display type is ambiguous, select a keyed service with `Type[key]` or use
the stable service ID from graph JSON.

## Review declarations proven unreachable

```bash
dart run better_effect_analyzer --unused
dart run better_effect_analyzer --unused --format json
```

Unused detection is deliberately conservative. Results are emitted only when
explicit `Module.complete` roots prove that a Module declaration and its
effective providers are unreachable. When a project has only inferred roots,
the command reports no proven unused declarations because an unreferenced
Module can itself be an application entry point.

Dynamic Module selection, reflection, generated host integration, and arbitrary
control flow remain outside this proof boundary. Treat the output as an
architecture-review input rather than an automatic deletion instruction.

## CI artifacts

Generate a versioned graph artifact:

```bash
mkdir -p build/better_effect
dart run better_effect_analyzer \
  --graph \
  --format json \
  --output build/better_effect/graph.json
```

The existing diagnostic JSON remains unchanged when `--graph` is absent, so
current CI consumers do not need to migrate.

## GitHub code scanning with SARIF

```bash
dart run better_effect_analyzer \
  --format sarif \
  --output build/better_effect/diagnostics.sarif
```

SARIF represents diagnostics, while graph JSON represents architecture. They
are separate exports so a consumer never has to infer whether an edge is an
error.

A GitHub Actions workflow can upload the file with the official code-scanning
action:

```yaml
- name: Build better_effect SARIF
  run: >-
    dart run better_effect_analyzer
    --format sarif
    --output build/better_effect/diagnostics.sarif

- name: Upload SARIF
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: build/better_effect/diagnostics.sarif
```

## Architecture diagrams

DOT output can be rendered with Graphviz:

```bash
dart run better_effect_analyzer --graph --format dot > graph.dot
dot -Tsvg graph.dot > graph.svg
```

Mermaid output can be committed beside architecture documentation or embedded
in a compatible Markdown renderer:

```bash
dart run better_effect_analyzer --graph --format mermaid > graph.mmd
```

Node IDs are generated deterministically from sorted service identities, so the
same source graph produces stable output across runs.

## Public Dart API

The graph can be embedded without invoking the CLI:

```dart
final analysis = await BetterEffectGraphChecker(root).analyze();
final graph = analysis.graph;

final module = graph.explainModule('appModule');
final paths = graph.whyService('Database');
final unused = graph.unusedDeclarations();
final json = BetterEffectGraphRenderer.graph(
  graph,
  format: BetterEffectGraphFormat.json,
);
```

`check()` remains available for callers that need diagnostics only, and
`graph()` is a convenience for callers that need only the immutable graph.

## Performance budget

Graph export reuses the same resolved-unit pass and project index used by the
existing graph checker. Building the public model adds one deterministic linear
projection over Modules, effective providers, services, dependencies, and
diagnostics. It must not trigger a second analyzer traversal or resolve source
files again.

Renderer budgets are linear in the exported graph size. `--explain` is linear
in the selected Module environment, `--unused` is linear in Module composition,
and `--why` performs a breadth-first search over the selected root dependency
subgraph while avoiding cycles.

For large projects, record the analyzer duration and graph entity counts in CI.
A change that materially increases runtime should include a fixture or benchmark
that isolates the new graph phase; do not compare wall-clock numbers collected
on different SDKs or machines.

## Static-analysis boundary

Generated Dart files ending in `.g.dart`, `.freezed.dart`, `.mocks.dart`, and
`.config.dart` remain excluded by default, matching the diagnostic checker.
Use `--include-tests` when test Modules are intentionally part of the exported
architecture.
