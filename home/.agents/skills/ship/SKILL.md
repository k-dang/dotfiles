---
name: ship
description: Finish, clean up, prove, review, and file work as a PR. Merges only when asked.
disable-model-invocation: true
---

# Ship

Take the request, or the work already on this branch, to a ready PR. The user has handed it off and may not be watching, so carry it through every step and make routine decisions yourself.

This request grants permission to commit and push this branch, use `--force-with-lease` on it after a rebase, and use the test methods proof needs. It grants merging only when the request says to merge, such as `/ship and merge`.

## Steps

1. **Scope.** Resolve the base: the existing PR's base, the parent branch for stacks, otherwise the repo default. On the default branch, create a branch first. Set a scope fence from the user's original request and the diff. Done when the base is known, the worktree holds no unrelated changes, and the fence is written down in one or two sentences.
2. **Finish.** Complete the goal from the user's request with the smallest change that works. With no new goal, take the work on this branch as it stands. Done when the request is implemented.
3. **Clean up.** Run `simplify`, then `deslop`.
4. **Prove.** Use the repo's `verify-*` skill when it has one, and run the checks its CI runs. Collect the evidence `file-pr` requires. Done when you have observed evidence yourself in this session for every behavior change in the diff.
5. **Review.** Run `git diff --shortstat` against the base. At 300 or more changed lines, run the `thermo-nuclear-code-quality-review` agent with the diff and changed files, or follow that skill's `SKILL.md` directly in a harness without the agent. Fix findings inside the fence and re-prove any behavior they change. Done when the diff is under 300 lines, or every finding is fixed or declined with a reason.
6. **File.** Commit, rebase onto the latest base, and push. Recheck behavior after any meaningful conflict fix. Run `file-pr`, adding one line that says how the change was proved.
7. **Babysit.** Run `babysit-pr` on the PR until its merge gate reports `MERGE_READY`, `AWAITING_REVIEW`, `BLOCKED`, or `WATCH_COMPLETE` on the current remote head. These overrides take precedence:
   - Use a 30-minute watch.
   - Use this skill's scope fence.
8. **Close out.** With merge granted and `MERGE_READY`, merge with the method the repo uses and wait until GitHub reports the PR as merged. Otherwise leave the PR open and unmerged. Stop the PR watch, then report the PR link, final state, proof, review outcome, and each decision you made for the user.

## Asking the user

Ask only when you cannot continue alone, using your harness's question tool, such as `AskUserQuestion`, so the thread shows it is waiting. Include the PR link, the blocker, and the options with your recommendation first. With no question tool, leave the PR open and unmerged and start your final message with the question.

- You cannot prove a change.
- The goal is ambiguous in a way that changes the result.
- The next step touches production, deletes data, reaches outside the repo, or force-pushes another branch.
- The merge gate cannot pass, and you cannot fix that yourself.

Merge through branch protection as configured. Merging bypasses such as `--admin` always need the user.
