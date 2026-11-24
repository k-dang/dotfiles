---
name: announce-pr
description: Draft a paste-ready Slack post for an open PR
disable-model-invocation: true
---

# Announce PR

Hand the user a one-line Slack post for an open PR that reads like the others in the channel. The user pastes the post; your output is the text.

## 1. Resolve the PR and channel

Use the PR number or URL if given, otherwise the PR for the current branch. Collect its URL, repo name, and title.

The channel comes from the user's arguments. When none is named, ask for it before step 2.

## 2. Read the channel

Read the latest ~25 messages in the channel with the Slack MCP, looking it up by name. On a rate limit, wait the `retry_after` it reports and retry once.

The user's own earlier posts set the format; fall back to the channel's most common shape when they have none. When the channel has no PR posts to copy, use:

```
[`<repo>`] <what changed> <PR URL>
```

## 3. Draft the post

One line in a code block, in that format, usually under ~15 words. Say what the PR does, the way an engineer would: start with a verb and name the thing that changed with everyday engineering words like mutation, column, flag, alert or task. Put a scope limit in parentheses, e.g. "(admin only)". Leave out benefits and selling points such as "all-or-nothing", "logged under their name" or "so ops can…"; the PR has those. Avoid class and method names. End a refactor with "No behaviour change". Use the bare PR URL, with no `< >` around it or any other text; Slack unfurls it.

```
[`billing-api`] Expose new mutation to void batch of draft invoices (admin only) https://github.com/acme/billing-api/pull/1234
```
