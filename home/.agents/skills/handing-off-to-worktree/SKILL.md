---
name: handing-off-to-worktree
description: Hand off a scoped code change to a fresh agent session in its own git worktree, with a self-contained brief. Use when the user asks to hand off, spin up, or start a fix or feature in a new worktree, or when another skill fans work out to parallel sessions.
---

# Handing off to a worktree

One hand-off is one branch, one worktree, one agent session, one brief. The session knows only what the brief says, so the brief is the work.

`scripts/handoff.sh` does the mechanics: creates the worktree from a fresh base and starts the agent through a backend (default `herdr-app`). Run it with no arguments for its options.

## 1. Settle the hand-off

For each hand-off, decide:

- **Scope:** the single change, its seam (component, file, method), and what it must leave alone.
- **Slug and branch:** a kebab-case slug naming the change (`retry-failed-webhooks`). The branch defaults to the slug; when the user wants a prefix, use a team or area prefix (`payments/retry-failed-webhooks`), never a person's name.
- **Siblings:** every open PR, branch, or other hand-off in this batch touching nearby code. These become the brief's Siblings section.
- **Agent setup:** `claude-opus-5-5`, effort `medium`, permission mode `auto`, base `origin/main`, unless the user says otherwise.

Done when every hand-off has a scope the user approved, a slug, its siblings named, and an agent setup. Approval of the fix in conversation counts; ask only about what is still open.

## 2. Write the brief

Fill [`brief-template.md`](brief-template.md) for each hand-off and save it to the scratchpad (one file per hand-off).

Done when each brief carries the real case's evidence, every rule as behaviour, the siblings, the regression cases, and the finish line.

## 3. Start the session

```bash
<skill-dir>/scripts/handoff.sh --repo <repo> --slug <slug> [--branch <branch>] \
  --name "<fix|feat>: <short title>" --task-file <brief>
```

Run one call per hand-off. `--dry-run` prints the commands without creating anything. The script refuses an existing worktree path or branch; pick another slug rather than reusing one.

Done when every call printed its JSON line (`backend`, `branch`, `worktree`, `session`).

## 4. Report

Show one row per hand-off: session name, `session` address, branch, and what it changes. Name the overlaps between sessions and where a rebase is likely. To check on a session later, read its address with the backend's reader (`hc read <address>` for `herdr-app`).

## Other tools

Backends live in `scripts/backends/`; read [`scripts/backends/README.md`](scripts/backends/README.md) to add one for a tool other than Herdr app.
