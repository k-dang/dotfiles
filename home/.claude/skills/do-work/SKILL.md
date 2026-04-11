---
name: do-work
description: Default workflow for executing a unit of work in a repository — scope and plan, implement, then validate via the repository's own feedback loops. Use whenever the user asks you to build, add, fix, refactor, migrate, or implement anything non-trivial in a codebase. This is the right skill to reach for any time a task involves understanding existing code, making changes, and verifying those changes actually work. Prefer this over diving straight into edits whenever the task is larger than a single obvious line change.
disable-model-invocation: true
---

# Do Work

A unit of work is not "done" when the edits land — it's done when the repository's own feedback loops say so. This skill is the default workflow for any non-trivial task: plan it, implement it, then prove it works using whatever the repo already has for validation.

## Workflow

Three phases, in order, none skipped:

1. **Plan** — Understand before you touch. Cheap to throw away a plan, expensive to throw away code.
2. **Implement** — Execute the plan in the smallest coherent steps you can.
3. **Validate** — Let the repository tell you whether you're done. Your opinion doesn't count; the feedback loop does.

The reason the order matters: planning prevents wasted implementation, and validation catches the things planning missed. Skipping either end of the sandwich is how work ships broken.

### 1. Understand the task

Read any referenced plan or PRD. Explore the codebase to understand the relevant files, patterns, and conventions. If the task is ambiguous, ask the user to clarify scope before proceeding.

### 2. Plan the implementation (optional)

If the task has not already been planned, create a plan for it.

### 3. Identify feedback loops

This is the step most often skipped. Before you start implementing, figure out how this repository validates work, because that's what you'll need to make green at the end. Look for:

| Signal | Where to find it |
|---|---|
| Tests | `package.json` scripts, `Makefile`, `justfile`, `pyproject.toml`, `Cargo.toml`, `**/*test*`, `**/*spec*` |
| Type checks | `tsc`, `mypy`, `pyright`, `pyrefly`, `cargo check`, `go vet` |
| Linters / formatters | `eslint`, `ruff`, `biome`, `rustfmt`, `gofmt`, pre-commit hooks |
| Build | `npm run build`, `cargo build`, `go build`, `tsc --noEmit` |
| CI definitions | `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile` — treat these as ground truth for what "passing" means |
| Dev server / manual verify | `npm run dev`, `cargo run`, browser for UI changes |

Write down — in your head or in a task list — the specific commands you're going to run in Phase 5. If no feedback loop exists for the area you're changing, **creating one is part of the work**: a failing test you can make pass is worth more than any amount of careful code reading.

### 4. Implement

Execute the plan.

**For backend code**: use red/green/refactor, one test at a time in a tracer-bullet style.

1. Write a single failing test for the smallest vertical slice of behavior
2. Run the test — confirm it fails (red)
3. Write the minimum code to make it pass (green)
4. Repeat from step 1 for the next slice of behavior
5. Refactor if needed while keeping tests green

Each test should target one thin vertical slice through the system. Do not write all tests upfront — write one, make it pass, then move to the next.

### 5. Validate via the Repository's Feedback Loops

This is the phase that makes the work *done* rather than *probably done*. Run the feedback loops you identified in Phase 1c, in roughly this order (fastest and most specific first):

1. **Targeted tests** — Run the tests for the file or module you changed. Fast, specific, high signal.
2. **Type checker / compiler** — Catches whole classes of bugs before the test suite does.
3. **Linter / formatter** — Matches house style; often enforced by CI.
4. **Full test suite** — If the change is cross-cutting or the targeted tests are few, run the whole thing.
5. **Build** — If it ships as an artifact, make sure it actually builds.
6. **Runtime / dev server** — For UI or behavior changes, actually exercise the feature. Start the dev server and use it in a browser. Type checkers verify *code correctness*, not *feature correctness* — if you can't actually test the UI, say so explicitly rather than claiming success.
7. **Commit hooks** — If the repo has pre-commit hooks, let them run; don't bypass them with `--no-verify`.

#### Interpreting the results

- **All green:** The work is done. Report what you did and which feedback loops you ran. Avoid claiming success for loops you didn't actually run.
- **Red:** You are not done. Read the failure carefully — the error message is load-bearing information, not a nuisance. Form a specific hypothesis about what's wrong, make the smallest fix that tests it, and re-run. This is the core loop from the **feedback-loop** skill; load that skill if you find yourself iterating more than two or three times without convergence.
- **Ambiguous** (flaky tests, subjective visual output, missing measurement): Don't paper over it. Either make the signal deterministic (pin seeds, mock time, write an assertion-backed test) or escalate to the user with what you've observed.

#### If the repository has no feedback loop for what you changed

This is common and not an excuse to skip validation. Options, in order of preference:

1. **Write the test that should exist.** A new test that fails before your fix and passes after is the gold-standard validation.
2. **Write a repro script.** A small script or command that exercises the change end-to-end.
3. **Manual verification with explicit reporting.** Exercise the feature and describe exactly what you checked. Be honest about the gap: "I verified X and Y manually; I did not exercise Z because [reason]."

Adding the feedback loop is part of the work, not overhead on top of it — it pays dividends every future time this code changes.

### 6. Completion

A unit of work is complete when:

- The change the user asked for is in place
- The feedback loops you identified in Phase 3 are green (or their absence is explicitly acknowledged)
- You've reported, concisely, what changed and what you ran to validate it

Report with enough detail that the user can verify without re-deriving your work, but without re-summarizing the diff they can already read. Call out anything surprising you found, anything you deliberately didn't do, and anything still uncertain.

If the feedback loops don't pass and you can't make them pass, **do not report the work as done**. Report what's red, what you've tried, and what you think the blocker is.
