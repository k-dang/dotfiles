---
name: file-pr
description: File a concise pull request. Use when the user asks to file, open or create a PR.
---

# File PR

Before filing, check whether a PR for this branch already exists. Resolve the actual base — the existing PR's base if present, otherwise the parent branch for stacks or the repo default. Do not assume `origin/main`. Review the diff locally against that base to make sure its contents match the goal.

Before filing or pushing, run the repository's fast CI checks locally (lint, format, typecheck; find them in `.github/workflows` and the package scripts) and fix any failures. Do this even for docs-only changes, since formatters check those files too.

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

Throughout the description, write as one human talking to another: simple, coherent, concise language, no jargon or slang.

## Context gathering

Gather only what is needed to explain the change: the ticket/task artifacts, the complete diff against the base plus enough surrounding code to understand behavior and ownership, and `gh pr view` metadata / changed files when a PR already exists.

## Gather evidence

Before filing or updating, obtain evidence for the changed behavior:

- Visible UI changes require before/after screenshots of the base and changed versions at the same viewport and corresponding state. For new UI, capture an after-only preview. Use a recording when motion or interaction is needed to show the change.
- Functional changes require focused test or command results. For bug fixes, reproduce the failure on the base and show the corrected behavior on the changed version.
- Captures from running the real app count even when the change looks the same, such as a refactor or perf change. Embed them as after-only previews when they show a user path the change touches still working. Label each one with the path it proves.

For screenshots or recordings, load the `before-and-after` skill and follow its capture and PR attachment workflow. Embed the published media in the PR description.

If capture or verification is blocked, document the attempted step, concrete blocker, and missing evidence in the PR description.

Evidence in the description is for the reviewer, not a log of what you ran. Show only the results that demonstrate the changed behavior and that the reviewer can't get from CI or the diff. Do not list passing suites, lint, or individual test cases. Mention unverified paths only when a reviewer would assume they were covered.

BAD
> ❌ Targeted specs pass (212 examples). Parser: rejects `abc`, `-1`, `1e9`… Full suite passes (1,840 examples). Rubocop clean.

GOOD
> ✅ End to end: a 10% coupon applied at checkout turns a $50 order into $45 on the emailed receipt.

## Change outline

Captures show the actual UI behavior; the outline explains logic or structure. Default to a compact visual of the change, picked from the formats in `references/show-me.md`. Visuals sit beside the text and support it. They never replace the opener or the explanation. Evidence captures can serve as the outline when they explain the change.

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

## Merge risk

For changes with irreversible effects, impact beyond the changed component, or rollout/recovery requirements, briefly name who or what is affected and whether reverting the code fully restores the previous behavior. Note irreversible effects and any required rollout or recovery steps. Put this in a short section at the end of the description, or in the template's equivalent section.

## Report completion

Before reporting completion, inspect the rendered PR description. Every required capture, verification result, and outline must be present, with media loading correctly, or have a concrete blocker documented in the description.

After filing or updating, reply with the PR URL and a catch-up for the user. They took part in this thread but may have stepped away while you worked. The PR description is written for a reviewer who has never seen the work. The catch-up is for someone who has, so measure it against what they last saw and asked for, and skip anything that only repeats it. Do not restate or quote the description; the link is enough.

The catch-up is a digest read before opening the PR, so keep it skimmable in a few seconds: about five lines total. Include only the parts that apply, as short labeled lines rather than sections:

- **Differs from the ask**: where the result departs from what the user asked for or picked.
- **Decided without you**: choices the user might push back on.
- **Found along the way**: surprises that changed the plan.
- **Needs you**: actions only the user can take, such as decisions or cleanup.

Each item is one short clause naming the outcome. Leave out the reason or mechanism unless the user can't judge the item without it. Keep only what the user would act on or object to. Known gaps, edge cases, and anything else a reviewer needs belong in the PR description, not here.

If the work went exactly as agreed, say so in one line and list only what needs the user.

BAD
> ❌ **Opener, as written in the PR:** The new Inset layout puts the page in a raised card, but the old status bar still ran along the bottom… **Change outline:** AppShell ├─ ClassicFrame…

GOOD
> ✅ Built option A as picked.
> **Decided without you:** Classic footer now lives in ClassicFrame.
> **Found along the way:** CPU/RAM shows "—" briefly when the menu opens.
> **Needs you:** delete `origin/prototype/status-bar-placement` when done comparing.

Do not recap the steps you ran, reviews, or passing checks, and do not justify process choices.

