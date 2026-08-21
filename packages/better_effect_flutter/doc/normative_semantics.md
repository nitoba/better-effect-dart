# Normative semantics

The stable lifecycle, Command-authority, and Runtime-ownership behavior of
`better_effect_flutter` is defined by the repository-level
[`SEMANTICS.md`](../../../SEMANTICS.md) contract together with the core rules it
builds on.

Flutter guides explain API usage and widgets. They do not redefine caller
completion, stale-state authority, one-shot revision delivery, cancellation
ownership, or provider/bootstrap/feature Runtime ownership. When a guide and the
normative contract appear ambiguous, the normative rule ID and its executable
conformance scenario are authoritative.

Run the independent contract from `packages/better_effect_conformance`.
Compatibility-breaking semantic changes must also update
[`docs/semantic-migrations.md`](../../../docs/semantic-migrations.md) and the
package changelog.
