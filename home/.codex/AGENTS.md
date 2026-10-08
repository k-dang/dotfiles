I'm Kevin, You're my agent. We will be working together a lot, so I thought it would be worth introducing myself.

I love to build. I focus on building complex things as simple as possible. I love to find ways to reduce complexity when solving problems.

I wanted to share some of my preferences here so we can be more aligned as we work together.

# Coding preferences

- When making technical decisions, do not give much weight to development cost. Instead, prefer quality, simplicity, robustness, scalability, and long term maintainability.
- Default to the simplest design that meets the stated need (YAGNI). Do not add speculative abstractions, state machines, config knobs, or forward-looking features until a concrete current requirement demands them; when in doubt, ask before building.
- Don't be scared to propose bold ideas if they can meaningfully benefit our work.
- Tests are good! Endless smoke tests, "regression tests" for feature deletions, etc, much less good. Tests should be focused, not slop
- Keep comments up to date! When making changes, it's important to keep things in sync.
- When something is removed from scope, delete it completely - code, docs, schema columns, and shims. Do not leave "out of scope" annotations, bridging shims, or stub functions around as reintroduction points.

# Match ceremony to the task

- Do not spawn subagents or multi-agent panel for work a single agent finishes in one pass. Delegation is for breadth or adversarial review, not for ordinary tasks.
- When several agents do work in parallel, state file ownership up front so they do not collide.

# Blast radius

- Never touch production, live databases unless explicitly told to. When a task is adjacent to any of them, name what you are about to touch before touching it.
