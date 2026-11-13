---
name: finish-pr
description: Finish implemented work on this branch with cleanup, review, and a filed PR, with the user choosing which review findings to fix.
disable-model-invocation: true
---

# Finish PR

Take implemented work on this branch through cleanup and review to a filed PR. The user is present: they choose which review findings get fixed.

## Mode

Pick from `git diff --shortstat` against the base (the existing PR's base, the parent branch for stacks, otherwise the repo default), unless the user names one:

- **Light**: under ~150 changed lines, or a small UI tweak or fix. Run `deslop`, then `file-pr`.
- **Full**: everything else. Run every step below.

State the mode and line count in one line before starting.

## Steps

1. **Simplify.** Run `simplify`. Done when its fixes are applied.
2. **Quality review.** Spin up a subagent to run the `thermo-nuclear-code-quality-review` skill on the diff against the base. Present its findings as a numbered list with a recommended action for each, then stop. Done when the user has picked which findings to fix.
3. **Fix.** Apply exactly the findings the user picked. When the user asks which approach is simpler, compare the options and recommend one before changing code.
4. **Sol review.** Run `sol-loop` on the diff.
5. **Deslop.** Run `deslop`. Remove comments that restate the code; keep only those explaining a non-obvious why. Done when the diff carries no slop.
6. **File.** Run `file-pr`.
