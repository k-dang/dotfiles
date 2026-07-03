---
name: pr-ready
description: Drive the current diff through simplify and review loops until clean.
disable-model-invocation: true
---

# pr-ready

The pipeline runs in an isolated subagent so the main session never sees the loops' findings or file edits. Main session handles only pre-flight, confirm, and surfacing the final summary.

## In the main session

### 1. Pre-flight

Check there are uncommitted or unpushed changes on a non-default branch (not `main`/`master`). If not, stop and report.

### 2. Confirm

Confirm once with this exact prompt: *"Drive working tree to clean via simplify → review loop → thermo loop? (no commit, no push)"*. Wait for go.

### 3. Dispatch

Spawn one `claude` subagent via the Agent tool. Pass it the pipeline prompt below verbatim. Wait for it. Surface its returned summary verbatim and exit.

Do not run any pipeline step in the main session — that defeats the isolation.

## Pipeline prompt (for the subagent)

> Run the following pipeline against the current diff in this repository. Apply fixes to the working tree as you go. Do not commit, push, or open a PR. Return a one-line summary at the end.
>
> **Step A — Simplify.** Invoke the `simplify` skill via the Skill tool. Let it complete its full pass.
>
> **Step B — Review loop (cap 5 rounds).** Each round: spawn three `code-reviewer` subagents in parallel against the current diff via the Agent tool. Dedupe findings; apply every actionable fix to the working tree. Re-run a fresh round on the post-fix diff. Stop when a round returns zero actionable findings.
>
> **Step C — Thermo loop (cap 5 rounds).** Each round: spawn one `thermo-nuclear-code-quality-review` subagent via the Agent tool. Apply every actionable finding. Re-run. Stop when a round returns zero actionable findings.
>
> **Cap behaviour.** If a loop hits round 5 with findings still outstanding, stop the pipeline and return `"capped: <loop name>, <N findings remaining>"`. Otherwise return `"clean: review <X> rounds, thermo <Y> rounds"`.

## Failure

A subagent error or a hit round-cap halts the pipeline. Surface what the subagent reported, leave the working tree as-is, exit.
