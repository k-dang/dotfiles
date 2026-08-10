---
name: pr-ready
description: Drive the current diff through review loops until clean.
disable-model-invocation: true
---

# pr-ready

Drive the current working tree to a clean, PR-ready state: run an adversarial review
loop, then a strict thermo-nuclear review loop — applying fixes until each loop comes
back clean. No commit, no push, no PR.

This is the pi-native, parent-orchestrated port of the original Claude skill. pi
strips the `subagent` tool from child subagents, so the loops cannot run inside an
isolated orchestrator subagent. Instead the **main session owns the loop**: it
spawns fresh-context reviewer subagents in parallel, synthesizes their findings,
and uses a single `worker` to apply fixes. Use the `subagent` tool for all
delegation.

## 1. Pre-flight

Confirm there is work to review:

- The current branch is not the default branch (`main`/`master`). If it is, stop and
  report.
- There are uncommitted changes, OR commits ahead of the default branch. If the tree
  is clean and nothing is ahead, stop and report "nothing to do".

The **review base** is the merge-base with the default branch. Throughout, "the
current diff" means the diff from that base through the working tree (committed +
uncommitted changes).

## 2. Confirm

Ask once, verbatim:

> Drive working tree to clean via review loop → thermo loop? (no commit, no push)

Wait for an explicit go. Do not proceed otherwise.

## 3. Pipeline

Use the `subagent` tool. Keep all writes single-threaded: **reviewers never edit; one
`worker` applies fixes**. Prefer `async: true` and keep orchestrating while subagents
run. After each worker pass, recompute the current diff before the next round.

### Step A — Review loop (cap 5 rounds)

Each round:

1. Spawn **three fresh-context `reviewer` subagents in parallel** against the current
   diff. Give each a distinct angle chosen from the actual change — e.g.
   correctness/regressions, tests/validation, simplicity/maintainability; swap in
   security, type/boundary safety, or UX when the diff calls for it. Reviewers inspect
   the repo and diff directly from files and commands, rely on no conversation
   history, and must not edit files.
2. Dedupe findings across the three reviewers. Keep only **actionable** fixes; set
   aside speculative or purely optional nits.
3. If there are actionable fixes, launch **one** `worker` to apply exactly those fixes
   to the working tree. If fewer than 5 rounds have run, start a fresh round on the
   post-fix diff.
4. Stop the loop when a round returns zero actionable findings. If round 5 had
   actionable findings, finish its worker pass, record the cap, and continue to the
   thermo loop without starting review round 6.

### Step B — Thermo loop (cap 5 rounds)

Each round:

1. Spawn **one fresh-context `reviewer` subagent with
   `skill: thermo-nuclear-code-quality-review`** against the current diff.
2. Keep its actionable findings. If any, launch **one** `worker` to apply them. If
   fewer than 5 rounds have run, re-run on the post-fix diff.
3. Stop when a round returns zero actionable findings. If round 5 had actionable
   findings, finish its worker pass and stop without starting thermo round 6.

### Cap behaviour

A cap limits reviewer iterations, not fix application. Always apply actionable
findings from round 5.

- A review-loop cap is a **soft phase boundary**: record it, then continue to the
  thermo loop against the post-fix diff.
- A thermo-loop cap ends the pipeline only after its round-5 worker finishes.
- Never skip the thermo loop because the review loop capped.

When both loops return clean before their caps, report:

```
clean: review <X> rounds, thermo <Y> rounds
```

When the review loop caps but thermo returns clean, report:

```
completed: review 5 rounds capped after applying <N> final findings, thermo <Y> rounds clean
```

When thermo caps, report:

```
completed with unverified final fixes: thermo 5 rounds capped after applying <N> final findings
```

## 4. Failure

If a subagent errors, halt the pipeline. Surface what the subagent reported, leave
working tree as-is (do not revert applied fixes), and exit. A loop cap is not a
subagent failure; follow cap behaviour above. Never commit, push, or open a PR.
