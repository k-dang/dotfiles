---
name: finish-pr
description: Trigger this when the user says 'finish pr' or asks to finish the PR.
---

# Finish PR

Take implemented work on this branch through cleanup, review, and proof to a filed PR. The user is present: they choose which review findings get fixed.

The base is the existing PR's base, the parent branch for stacks, otherwise the repo default. Run every step for every change.

## Steps

1. **Simplify.** Run `simplify`. Done when its fixes are applied.
2. **Quality review.** Spin up a subagent to run the `thermo-nuclear-code-quality-review` skill on the diff against the base. Present its findings as a numbered list with a recommended action for each, then stop. Done when the user has picked which findings to fix.
3. **Fix.** Apply exactly the findings the user picked. When the user asks which approach is simpler, compare the options and recommend one before changing code.
4. **Sol review.** Run `sol-loop` on the diff.
5. **Deslop.** Run `deslop`. Remove comments that restate the code; keep only those explaining a non-obvious why. Done when the diff carries no slop.
6. **Prove.** Use the repo's `verify-*` skill when it has one, and run the checks its CI runs. For UI or runtime behavior, run the app and look at the change, since green mocked tests do not prove it. Show the user what you observed for each behavior change, and ask about any you could not prove. Done when you have observed evidence yourself in this session for every behavior change in the diff.
7. **File.** Run `file-pr`.
