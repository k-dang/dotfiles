# Effect reference standards

## Default repositories

Unless the user specifies a different reference set, use all three as the gold standards for Effect audits:

- OpenCode: `anomalyco/opencode`.
- T3 Code: `pingdotgg/t3code`.
- Effect-TS: `Effect-TS/effect`.

Explicit replacement repositories override this set; requests to add repositories extend it. The versioned `effect` package establishes the target's library contract; the full Effect repository supplies broader examples and tests.

## Optional investigation prompts

These questions can seed exploration of Effect implementations. Answer them using the fetched target version and consumer examples.

- Does composition preserve laziness, interruption, and context through runtime and Promise boundaries?
- Are expected failures modeled in the error channel, distinguished from defects, and recovered without hiding useful error information?
- Do services and layers expose dependencies and give their construction a clear owner?
- Do scopes and finalizers match resource lifetimes, including failure and interruption paths?
- Are fibers owned by an appropriate lifetime, and do concurrency and retries match the operation's ordering and idempotency requirements?
- Do schemas decode external data at its entry point and preserve useful validation failures?
- Do tests use the version's real Effect test utilities to exercise time, dependencies, resource release, and interruption where relevant?
