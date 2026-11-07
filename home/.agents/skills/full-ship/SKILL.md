---
name: full-ship
description: Finish, clean up, prove, review, and file work as a PR, stopping before merge.
disable-model-invocation: true
---

# Full Ship

Take the request, or the work already on this branch, to a ready PR. The user has handed it off and may not be watching, so carry it through every step and make routine decisions yourself.

This request grants permission to commit and push this branch, use `--force-with-lease` on it after a rebase, and use the test methods proof needs, even when a project file says to ask first.

## Steps

1. **Scope.** Resolve the base: the existing PR's base, the parent branch for stacks, otherwise the repo default. On the default branch, create a branch first. Set a scope fence from the user's original request and the diff. Done when the base is known, the worktree holds no unrelated changes, and the fence is written down in one or two sentences.
2. **Finish.** Complete the goal from the user's request with the smallest change that works. With no new goal, take the work on this branch as it stands. Done when the request is implemented.
3. **Clean up.** Run `simplify`, then `deslop`.
4. **Prove.** Use the repo's `verify-*` skill when it has one, and run the checks its CI runs. For UI or runtime behavior, run the app and look at the change, since green mocked tests do not prove it. Collect the evidence `file-pr` requires. Done when you have observed evidence yourself in this session for every behavior change in the diff.
5. **Review.** Run `git diff --shortstat` against the base. At 300 or more changed lines, spin up a subagent to run the `thermo-nuclear-code-quality-review` skill on the diff against the base. That skill is user-invoked, so have the subagent read its `SKILL.md` directly. Fix findings inside the fence and re-prove any behavior they change. Done when the diff is under 300 lines, or every finding is fixed or declined with a reason.
6. **File.** Commit, rebase onto the latest base, and push. Recheck behavior after any meaningful conflict fix. Run `file-pr`, adding one line that says how the change was proved.
7. **Babysit.** Run `babysit-pr` on the PR, with this skill's scope fence as the boundary for feedback. Prove each fix before pushing it. Done when `pr-wait` exits 0 on the current remote head, or it exits 1 for something you cannot resolve.
8. **Close out.** Fetch the base and check the live PR: confirm it is open, not a draft, and not set to merge without the user. If someone else merged it, report that instead. Report the PR link, final head, proof, review outcome, each decision you made for the user, and whether the PR is still open and unmerged.

## No merging

The user does the merge. Never merge, enable auto-merge, enter a merge queue, or push to the default branch.

Turn off auto-merge on any existing PR and remove it from any merge queue before work begins, check again before each push, and report any change.

## Asking the user

Ask only when you cannot continue alone, using your harness's question tool, such as `AskUserQuestion`, so the thread shows it is waiting. Include the PR link, the blocker, and the options with your recommendation first. With no question tool, leave the PR open and unmerged and start your final message with the question.

- You cannot prove a change.
- The goal is ambiguous in a way that changes the result.
- The next step touches production, deletes data, reaches outside the repo, or force-pushes another branch.
- `pr-wait` exits 1, and you cannot fix the cause yourself.
