---
name: pr-ready
description: Drive the current diff through simplify and review loops until clean.
disable-model-invocation: true
---

# pr-ready

The main session orchestrates directly. Nested Agent calls are unavailable in this harness, so a single outer subagent cannot fan out to `code-reviewer` / `thermo-nuclear-code-quality-review` — attempting it fails with "Agent tool unavailable in this session". Each subagent spawned below is prompted to return a **short summary of what it changed or found**, not full findings, to keep main-session context focused on orchestration.

## 1. Pre-flight

Check there are uncommitted or unpushed changes on a non-default branch (not `main`/`master`). If not, stop and report.

## 2. Step A — Simplify

Invoke the `simplify` skill via the Skill tool. Let it complete its full pass.

## 3. Step B — Review loop (cap 5 rounds)

Each round:

1. In a single message, spawn three `code-reviewer` subagents in parallel via the Agent tool. Prompt each to review the current diff and return **only** a compact JSON list of actionable findings (file, line, one-sentence description, one-sentence fix). No prose.
2. Dedupe findings across the three reports.
3. Apply every actionable fix to the working tree yourself (Edit/Write). Do not spawn a fixer subagent — nested Agent calls won't work.
4. If any fixes were applied, start a fresh round on the post-fix diff.

Stop when a round returns zero actionable findings. If round 5 completes with findings still outstanding, halt the pipeline and report `"capped: review, <N findings remaining>"`.

## 4. Step C — Thermo loop (cap 5 rounds)

Each round: spawn one `thermo-nuclear-code-quality-review` subagent via the Agent tool. Prompt it to return only a compact JSON list of actionable findings. Apply every actionable fix to the working tree. Re-run. Stop when a round returns zero actionable findings. If round 5 completes with findings still outstanding, halt and report `"capped: thermo, <N findings remaining>"`.

## 5. Summary

When both loops finish without hitting their cap, return `"clean: review <X> rounds, thermo <Y> rounds"`.

## Failure

A subagent error or a hit round-cap halts the pipeline. Surface what the subagent reported, leave the working tree as-is, exit. Do not commit, push, or open a PR from this skill.
