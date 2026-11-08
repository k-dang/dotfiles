# Brief template

The brief is the session's only context. Fill every section; delete a section only when it is genuinely empty.

```markdown
<One sentence: the change and where it lives (component, file, method).>

Context: <the real case that exposed it — account or record, the actual values, dates and amounts, the reject or error string verbatim. Concrete evidence, not a summary of it.>

Change:
- <each rule the change must implement, stated as behaviour>
- <what stays unchanged, so the session preserves it>

Siblings: <open PRs and branches touching nearby code, by number or branch name, and what each changes. "Read its diff (gh pr diff N) and stay compatible." Name files this session must not touch.>

Method: work test-first (tdd, writing-specs skills). Regression specs: <the specific cases, one per rule above>.

Done when: <component> specs and rubocop on changed files pass, and the work is committed on this branch with a short title. Do not push or open a PR.
```

## Writing it

- **Evidence over description.** "record X has field A = 2026-08-10 and field B = 2026-08-27, and fails with `<exact error>`" gives the session a test case; "B can end up after A" gives it a guess.
- **Rules as behaviour.** Say what the code must do for each case; leave the implementation to the session, and say so when you want it to choose a placement ("decide whether this belongs in X or Y; keep it in one place").
- **Siblings are file ownership.** Two sessions in the same method is a rebase; two sessions in the same file without knowing about each other is a conflict. Name every sibling.
- **The finish line is the user's.** Commit, no push, unless the user asked for more.
