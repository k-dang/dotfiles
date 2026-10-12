---
name: file-pr
description: File a concise pull request. Use when the user asks to file, open or create a PR.
---

# File PR

Before filing, check whether a PR for this branch already exists. Resolve the actual base — the existing PR's base if present, otherwise the parent branch for stacks or the repo default. Do not assume `origin/main`. Review the diff locally against that base to make sure its contents match the goal.

PR titles usually become commit messages, so follow the repository's title conventions. Look at recently merged PRs and Git history for examples. Prefer a concise, human-readable title that explains why the change matters:

BAD
> ❌ perf(server): negotiate permessage-deflate on the websocket

GOOD
> ✅ perf(server): cut websocket frame size by 70%+ with gzipping

Follow PR templates when they are available. Place visuals and evidence inside the template's existing sections (e.g. under "Changes").

Open the description with a simple explanation of the problem based on the user's original prompt, then briefly explain the solution. Do not lead with an implementation inventory:

BAD
> ❌ Removed implicit workspace carry-over from every "new thread" entry point (cmd +n / cmd+shift+o, sidebar v1/v2 buttons, command palette). New threads inherit only the project from context; branch, worktree, and env mode always come from the configured defaults. Deleted buildContextualThreadOptions, startNewThreadInProjectFromContext, and the v1 sidebar's seed-context machinery.

GOOD
> ✅ My "new worktree" default was ignored when starting new threads on existing worktrees. Super unintuitive. Now your preferences always apply.

## Context gathering

Gather only what is needed to explain the change: the ticket/task artifacts, the complete diff against the base plus enough surrounding code to understand behavior and ownership, and `gh pr view` metadata / changed files when a PR already exists.

## Gather evidence

Before filing or updating, obtain evidence for the changed behavior:

- Visible UI changes require before/after screenshots of the base and changed versions at the same viewport and corresponding state. For new UI, capture an after-only preview. Use a recording when motion or interaction is needed to show the change.
- Functional changes require focused test or command results. For bug fixes, reproduce the failure on the base and show the corrected behavior on the changed version.

For screenshots or recordings, load the `before-and-after` skill and follow its capture and PR attachment workflow. Embed the published media in the PR description. Diagrams explain logic or structure; captures show the actual UI behavior.

If capture or verification is blocked, document the attempted step, concrete blocker, and missing evidence in the PR description.

## Change outline

Load the `show-me` skill for every PR and default to a compact visual showing the change. Use `references/show-me.md` for PR formatting. Evidence captures can serve as the outline when they explain the change.

Omit the explanatory outline only for straightforward local or mechanical edits fully explained by the opener, or an explicitly minimal template. Evidence requirements still apply.

Place the outline after the opener and scale it to the change:

- Simple single-concern PRs get one small visual showing the core logic or data flow.
- Complex PRs get a fuller outline. Complex means the reviewer could misread scope without it: multiple areas, cross-package changes, API/SQL contract changes, migrations, or surprising decisions/omissions.

Include only views that help explain this PR, ordered to tell the story. Omit categories that did not change.

- Endpoint request/response contracts and SQL table / column changes.
- Key data structure / type changes.
- Pseudocode for changed business logic.
- Shallow file tree showing changed responsibilities.
- React component tree changes, including important hooks, state, and package boundaries.
- Call-tree, control-flow, or data-flow changes.

Prefer `diff` blocks when showing changes to an existing shape. Show the complete target shape when most of it is new or diff notation would obscure ownership or order.

Write as one human talking to another: simple, coherent, concise language, no jargon or slang.

## Merge risk

For changes with irreversible effects, impact beyond the changed component, or rollout/recovery requirements, briefly name who or what is affected and whether reverting the code fully restores the previous behavior. Note irreversible effects and any required rollout or recovery steps.

## Report completion

Before reporting completion, inspect the rendered PR description. Every required capture, verification result, and outline must be present, with media loading correctly, or have a concrete blocker documented in the description.

After filing or updating, respond with the PR URL and a brief summary of the outcome. Mention verification results, caveats, or decisions that affect the user's next step. Include changed-file details only when they help the user locate something they need to inspect or act on.

