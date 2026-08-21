library;

/// One stable normative rule from the repository semantic contract.
final class ConformanceRule {
  const ConformanceRule({
    required this.id,
    required this.area,
    required this.summary,
  });

  final String id;
  final String area;
  final String summary;
}

/// Stable MUST/MUST NOT rules defined by `SEMANTICS.md`.
const normativeConformanceRules = <ConformanceRule>[
  ConformanceRule(
    id: 'EFFECT-01',
    area: 'Effect and Exit',
    summary: 'Effect construction is lazy',
  ),
  ConformanceRule(
    id: 'EFFECT-02',
    area: 'Effect and Exit',
    summary: 'Typed failures stay typed',
  ),
  ConformanceRule(
    id: 'EFFECT-03',
    area: 'Effect and Exit',
    summary: 'Unhandled throws stay defects',
  ),
  ConformanceRule(
    id: 'EFFECT-04',
    area: 'Effect and Exit',
    summary: 'run and runExit preserve their public channels',
  ),
  ConformanceRule(
    id: 'EFFECT-05',
    area: 'Effect and Exit',
    summary:
        'Logical interruption remains authoritative while physical work drains',
  ),
  ConformanceRule(
    id: 'OUTCOME-01',
    area: 'Outcome precedence',
    summary: 'Success plus successful cleanup stays success',
  ),
  ConformanceRule(
    id: 'OUTCOME-02',
    area: 'Outcome precedence',
    summary: 'Success plus failed cleanup becomes a defect',
  ),
  ConformanceRule(
    id: 'OUTCOME-03',
    area: 'Outcome precedence',
    summary: 'Typed failure plus successful cleanup stays failure',
  ),
  ConformanceRule(
    id: 'OUTCOME-04',
    area: 'Outcome precedence',
    summary: 'Typed failure survives failed cleanup',
  ),
  ConformanceRule(
    id: 'OUTCOME-05',
    area: 'Outcome precedence',
    summary: 'Defect plus successful cleanup preserves the defect',
  ),
  ConformanceRule(
    id: 'OUTCOME-06',
    area: 'Outcome precedence',
    summary: 'Defect plus failed cleanup preserves both defects',
  ),
  ConformanceRule(
    id: 'OUTCOME-07',
    area: 'Outcome precedence',
    summary: 'Interruption plus successful cleanup stays interruption',
  ),
  ConformanceRule(
    id: 'OUTCOME-08',
    area: 'Outcome precedence',
    summary: 'Interruption survives failed cleanup',
  ),
  ConformanceRule(
    id: 'OUTCOME-09',
    area: 'Outcome precedence',
    summary: 'Observer failures never replace Effect outcomes',
  ),
  ConformanceRule(
    id: 'SCOPE-01',
    area: 'Scope and resources',
    summary: 'Scope cleanup is child-first and LIFO',
  ),
  ConformanceRule(
    id: 'SCOPE-02',
    area: 'Scope and resources',
    summary: 'Late acquisition is released exactly once',
  ),
  ConformanceRule(
    id: 'SCOPE-03',
    area: 'Scope and resources',
    summary: 'Release receives the closing outcome',
  ),
  ConformanceRule(
    id: 'SCOPE-04',
    area: 'Scope and resources',
    summary: 'Cleanup failures aggregate deterministically',
  ),
  ConformanceRule(
    id: 'SCOPE-05',
    area: 'Scope and resources',
    summary: 'Scope close is idempotent',
  ),
  ConformanceRule(
    id: 'SCOPE-06',
    area: 'Scope and resources',
    summary: 'Closing or closed Scopes reject new ownership',
  ),
  ConformanceRule(
    id: 'RUNTIME-01',
    area: 'Runtime',
    summary: 'Runtime lifecycle rejects new work after closing starts',
  ),
  ConformanceRule(
    id: 'RUNTIME-02',
    area: 'Runtime',
    summary: 'Graceful shutdown requests cooperative cancellation',
  ),
  ConformanceRule(
    id: 'RUNTIME-03',
    area: 'Runtime',
    summary: 'Non-cooperative work remains physically owned',
  ),
  ConformanceRule(
    id: 'RUNTIME-04',
    area: 'Runtime',
    summary: 'Admitted executions retain service resolution during shutdown',
  ),
  ConformanceRule(
    id: 'RUNTIME-05',
    area: 'Runtime',
    summary: 'Timeout retains late resource ownership',
  ),
  ConformanceRule(
    id: 'ENV-01',
    area: 'Runtime environments',
    summary: 'Execution Modules shadow and fall back to root services',
  ),
  ConformanceRule(
    id: 'ENV-02',
    area: 'Runtime environments',
    summary: 'Child Runtimes shadow and fall back to parent services',
  ),
  ConformanceRule(
    id: 'ENV-03',
    area: 'Runtime environments',
    summary: 'Parent shutdown closes children before parent resources',
  ),
  ConformanceRule(
    id: 'CONCURRENCY-01',
    area: 'Concurrency',
    summary: 'Bounded collection work respects maximum concurrency',
  ),
  ConformanceRule(
    id: 'CONCURRENCY-02',
    area: 'Concurrency',
    summary: 'Collection output preserves input order',
  ),
  ConformanceRule(
    id: 'CONCURRENCY-03',
    area: 'Concurrency',
    summary: 'Failure selection is deterministic by input index',
  ),
  ConformanceRule(
    id: 'CONCURRENCY-04',
    area: 'Concurrency',
    summary: 'Failure stops new scheduling and drains started work',
  ),
  ConformanceRule(
    id: 'CONCURRENCY-05',
    area: 'Concurrency',
    summary: 'Interruption stops new scheduling and drains started work',
  ),
  ConformanceRule(
    id: 'RETRY-01',
    area: 'Retry',
    summary: 'Typed failures retry according to maxAttempts',
  ),
  ConformanceRule(
    id: 'RETRY-02',
    area: 'Retry',
    summary: 'Defects are not retried by typed-failure policy',
  ),
  ConformanceRule(
    id: 'RETRY-03',
    area: 'Retry',
    summary: 'Each attempt Scope closes before the next attempt',
  ),
  ConformanceRule(
    id: 'RETRY-04',
    area: 'Retry',
    summary: 'Interruption or cleanup failure stops retry scheduling',
  ),
  ConformanceRule(
    id: 'COMMAND-01',
    area: 'Flutter Commands',
    summary: 'Visible state preserves outcome authority',
  ),
  ConformanceRule(
    id: 'COMMAND-02',
    area: 'Flutter Commands',
    summary: 'Accepted callers retain their own completion',
  ),
  ConformanceRule(
    id: 'COMMAND-03',
    area: 'Flutter Commands',
    summary: 'drop does not duplicate active work',
  ),
  ConformanceRule(
    id: 'COMMAND-04',
    area: 'Flutter Commands',
    summary: 'latest prevents stale state replacement',
  ),
  ConformanceRule(
    id: 'COMMAND-05',
    area: 'Flutter Commands',
    summary: 'queue starts accepted callers in request order',
  ),
  ConformanceRule(
    id: 'COMMAND-06',
    area: 'Flutter Commands',
    summary: 'Queue cancellation interrupts callers that never start',
  ),
  ConformanceRule(
    id: 'COMMAND-07',
    area: 'Flutter Commands',
    summary: 'Legacy concurrency values map to equivalent policies',
  ),
  ConformanceRule(
    id: 'COMMAND-08',
    area: 'Flutter Commands',
    summary: 'One-shot listener revisions are delivered at most once',
  ),
  ConformanceRule(
    id: 'COMMAND-09',
    area: 'Flutter Commands',
    summary: 'Command interruption retains physical Runtime ownership',
  ),
  ConformanceRule(
    id: 'COMMAND-10',
    area: 'Flutter Commands',
    summary: 'Timed policies use Runtime-owned EffectClock deterministically',
  ),
  ConformanceRule(
    id: 'OWNERSHIP-01',
    area: 'Flutter ownership',
    summary: 'External providers never close supplied Runtimes',
  ),
  ConformanceRule(
    id: 'OWNERSHIP-02',
    area: 'Flutter ownership',
    summary: 'Owned providers close Runtimes exactly once',
  ),
  ConformanceRule(
    id: 'OWNERSHIP-03',
    area: 'Flutter ownership',
    summary: 'Bootstrap closes stale startup Runtimes',
  ),
  ConformanceRule(
    id: 'OWNERSHIP-04',
    area: 'Flutter ownership',
    summary: 'Feature scope owns only its child Runtime',
  ),
];

final Map<String, ConformanceRule> normativeConformanceRulesById =
    <String, ConformanceRule>{
      for (final rule in normativeConformanceRules) rule.id: rule,
    };

ConformanceRule conformanceRule(String id) {
  final rule = normativeConformanceRulesById[id];
  if (rule == null) {
    throw ArgumentError.value(id, 'id', 'Unknown normative conformance rule.');
  }
  return rule;
}
