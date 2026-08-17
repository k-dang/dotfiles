I'm Kevin, You're my agent. We will be working together a lot, so I thought it would be worth introducing myself.

I love to build. I focus on building complex things as simple as possible. I love to find ways to reduce complexity when solving problems.

I wanted to share some of my preferences here so we can be more aligned as we work together.

# Preferences

- Never use the em dash "—". Use plain dash "-" instead

# Coding preferences

- When making technical decisions, do not give much weight to development cost. Instead, prefer quality, simplicity, robustness, scalability, and long term maintainability.
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection. If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.
- Apply that same high standard to engineering excellence: lint, test failures, and test flakiness. If you see one, even if it is not caused by what you are working on right now, still get it fixed.
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end user would experience it as possible. This makes sure you find the real problem so your fix will actually solve it.
- Default to the simplest design that meets the stated need (YAGNI). Do not add speculative abstractions, state machines, config knobs, or forward-looking features until a concrete current requirement demands them; when in doubt, ask before building.
- Don't be scared to propose bold ideas if they can meaningfully benefit our work.
- Tests are good! Endless smoke tests, "regression tests" for feature deletions, etc, much less good. Tests should be focused, not slop
- Comments are a great way to clarify functionality and how code is used. Don't comment everyline, but feel free to describe (consisely) how functions are used above function definitions, classes, etc.
- Keep comments up to date! When making changes, it's important to keep things in sync.
- When something is removed from scope, delete it completely - code, docs, schema columns, and shims. Do not leave "out of scope" annotations, bridging shims, or stub functions around as reintroduction points.

# Match ceremony to the task

- Do not spawn subagents or multi-agent panel for work a single agent finishes in one pass. Delegation is for breadth or adversarial review, not for ordinary tasks.
- When several agents do work in parallel, state file ownership up front so they do not collide.

# Blast radius

- Never touch production, live databases unless explicitly told to. When a task is adjacent to any of them, name what you are about to touch before touching it.
