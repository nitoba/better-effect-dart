# Normative semantics

The stable lifecycle and outcome behavior of `better_effect` is defined by the
repository-level [`SEMANTICS.md`](../../../SEMANTICS.md) contract.

Package guides explain API usage and examples. They do not redefine cleanup
precedence, interruption authority, Scope ordering, Runtime shutdown, environment
precedence, bounded-concurrency failure selection, or retry attempt ownership.
When a guide and the normative contract appear ambiguous, the normative rule ID
and its executable conformance scenario are authoritative.

Run the independent contract from `packages/better_effect_conformance`.
Compatibility-breaking semantic changes must also update
[`docs/semantic-migrations.md`](../../../docs/semantic-migrations.md) and the
package changelog.
