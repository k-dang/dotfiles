# Review rubric

Apply every relevant lens. Support findings with specific code and consequences, extending beyond the diff to understand contracts and reachable paths.

## Correctness and recovery

- Does behavior satisfy the stated intent on both happy and failure paths?
- Trace empty inputs, boundary values, missing data, encoding, coercion, and numerical limits where reachable.
- Check error propagation, stale state, cancellation, resource cleanup, and ownership.
- Follow concurrent access to shared state; identify real races and the structural ownership or synchronization needed.
- Examine retries, repeated execution, and crashes between related updates. Does recovery restore the intended invariants?

## Root cause and contracts

- Follow callers, callees, and types before deciding whether the fix belongs at this layer.
- Identify guards, retries, casts, or fallbacks that hide a broken invariant instead of restoring it.
- Check whether external inputs are validated at the right boundary and internal types express the resulting guarantees.
- Prefer enforceable contracts over comments or conventions when they prevent a demonstrated failure.

## Structural simplification

Be ambitious about behavior-preserving simplification: look for a reframing that removes branches, helpers, modes, or layers rather than redistributing the same complexity.

- Does the change fit the canonical module and reuse existing capabilities?
- Do ad-hoc branches scatter feature logic through unrelated flows?
- Are abstractions deep enough to earn their indirection, or are they wrappers around a simple operation?
- Does the data model make access patterns and ownership clear?
- Can unnecessary optionality or cast-heavy code be replaced by a clearer boundary?
- Are new compatibility paths required by real consumers or merely speculative?
- Are related updates atomic where necessary? Is serialized independent work creating a concrete problem?
- Does file growth mix responsibilities or make changes materially harder? File length alone is not a blocker.

Support structural findings with a concrete alternative and benefit. Simple working inline code can be better than premature abstraction. Respect established project constraints rather than demanding a preferred architecture.

## Verification

- Do tests exercise externally visible behavior, failure paths, and relevant integration boundaries?
- Does a bug fix include evidence that would fail before the fix and pass after it?
- Are assertions checking the real invariant rather than a proxy such as cached status?
- Is asynchronous or delegated work checked against actual artifacts rather than self-reported success?
- Distinguish tests inspected from tests executed and passing results from assumptions.

## Complexity budget

- Identify unnecessary configuration, generic mechanisms, dead code, and “just in case” paths.
- Prefer deleting incidental complexity over adding a framework or spreading it across files.
- Check whether the user-visible value justifies the new modes and moving parts.
- Account for migration plans and external consumers before recommending removal of scaffolding.

## Security

Trace untrusted input to the actual operation and establish exploitability or the violated contract.

- Injection into SQL, shell commands, evaluation, markup, or file paths.
- Authentication, authorization, and tenant/isolation boundaries.
- Secrets or sensitive data exposed through code, logs, errors, or new outputs.
- Time-of-check/time-of-use races in security-sensitive operations.

A speculative dangerous-looking sink is an investigation lead, not a proven vulnerability.
