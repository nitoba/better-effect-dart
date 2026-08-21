# Semantic migration ledger

This file records compatibility-breaking changes to the normative lifecycle and
outcome contract in [`SEMANTICS.md`](../SEMANTICS.md).

A semantic migration entry is required whenever a MUST/MUST NOT rule changes.
The same pull request must update the affected package changelog(s) and the
matching executable conformance scenario.

## Entry format

```text
## YYYY-MM-DD — RULE-ID — short title

Affected packages: better_effect, better_effect_flutter

Previous behavior:
...

New behavior:
...

Why:
...

Migration:
...
```

## 2026-08-21 — normative baseline

Affected packages: `better_effect`, `better_effect_flutter`

This is the first versioned normative contract. It does not change an existing
normative rule; it promotes lifecycle/outcome behavior already proven across the
0.2–0.4 implementation work into an explicit compatibility baseline.

Future changes to the stable rules must add a new entry above this baseline.
