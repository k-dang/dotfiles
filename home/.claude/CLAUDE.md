# Personal Preferences

- Never use the em dash "—". Use plain dash "-" instead
- Never manually modify CHANGELOG.md files or any files that are marked as auto-generated
- When making technical decisions, do not give much weight to development cost. Instead, prefer quality, simplicity, robustness, scalability, and long term maintainability.
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end user would experience it as possible. This makes sure you find the real problem so your fix will actually solve it.
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection. If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.
- Apply that same high standard to engineering excellence: lint, test failures, and test flakiness. If you see one, even if it is not caused by what you are working on right now, still get it fixed.
- Default to the simplest design that meets the stated need (YAGNI). Do not add speculative abstractions, state machines, config knobs, or forward-looking features until a concrete current requirement demands them; when in doubt, ask before building.
- When something is removed from scope, delete it completely - code, docs, schema columns, and shims. Do not leave "out of scope" annotations, bridging shims, or stub functions around as reintroduction points.
- Check for an already-running dev server and reuse it instead of starting a new one. If you do start any dev servers, kill them before finishing the task.

## Philosophy

This codebase will outlive you. Every shortcut becomes someone else's burden. Every hack compounds into technical debt that slows the whole teamdown.

You are not just writing code. You are shaping the future of this product. The patterns you establish will be copied. The corners you cut will be cut again.

Fight entropy. Leave the codebase better than you found it.
