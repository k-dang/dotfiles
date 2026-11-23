---
name: announce-pr
description: Watch a PR's CI and draft a paste-ready post
disable-model-invocation: true
---

# Announce PR

Two jobs for one open PR, run side by side: tell the user when CI finishes, and hand them a one-line Slack post that reads like the others. The user pastes the post; your output is the text.

## 1. Resolve the PR and channel

Use the PR number or URL if given, otherwise the PR for the current branch. Collect its URL, repo name, and title.

The channel comes from the user's arguments. When none is named, ask for it before step 3.

## 2. Start the CI watch

Run in the background, so drafting continues while it waits:

```bash
gh pr checks <PR> --watch --interval 60
```

Done when every check that isn't skipped has passed or failed.

## 3. Read the channel

Read the latest ~25 messages in the channel with the Slack MCP, looking it up by name. On a rate limit, wait the `retry_after` it reports and retry once.

The user's own earlier posts set the format; fall back to the channel's most common shape when they have none. When the channel has no PR posts to copy, use:

```
[`<repo>`] <what changed> <PR URL>
```

## 4. Draft the post

One line in a code block, in that format, usually under ~15 words. Say what the PR does, the way an engineer would: start with a verb and name the thing that changed with everyday engineering words like mutation, column, flag, alert or task. Put a scope limit in parentheses, e.g. "(admin only)". Leave out benefits and selling points such as "all-or-nothing", "logged under their name" or "so ops can…"; the PR has those. Avoid class and method names. End a refactor with "No behaviour change". Use the bare PR URL, with no `< >` around it or any other text; Slack unfurls it.

```
[`billing-api`] Expose new mutation to void batch of draft invoices (admin only) https://github.com/acme/billing-api/pull/1234
```

## 5. Report CI

When the watch ends, say plainly that CI passed, or name each failed check with its link. A failure in a test that passed locally and touches nothing the PR changed is a likely flake: say so and suggest a rerun. Fixing failures is `babysit-pr`'s job; point there.

Done when the user has the post and the CI result.
