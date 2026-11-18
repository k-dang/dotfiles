---
name: announce-pr
description: Watch a PR's CI and draft a paste-ready post for #payment-cards-prs.
disable-model-invocation: true
---

# Announce PR

Two jobs for one open PR, run side by side: tell the user when CI finishes, and hand them a one-line Slack post that reads like the others in #payment-cards-prs. The user pastes the post; your output is the text.

## 1. Resolve the PR

Use the PR number or URL if given, otherwise the PR for the current branch. Collect its URL, repo name, and title.

## 2. Start the CI watch

Run in the background, so drafting continues while it waits:

```bash
gh pr checks <PR> --watch --interval 60
```

Done when every check that isn't skipped has passed or failed.

## 3. Read the channel

Read the latest ~25 messages in #payment-cards-prs (channel `C071TNWD3GU`; look it up by name if that fails) with the Slack MCP. On a rate limit, wait the `retry_after` it reports and retry once.

The user's own earlier posts set the format; fall back to the channel's most common shape when they have none. Today the user writes:

```
[`risk-service`] Add card product and credit limit columns to static approvals https://github.com/wealthsimple/risk-service/pull/4577
```

## 4. Draft the post

One line in a code block, in that format, under ~25 words. Write it for a teammate skimming the channel, not for the PR's reviewer: the area it touches, what changed, and why it matters to them, the way you'd say it out loud. Don't lift the PR's opener or title; those are written for review and use code-level terms like class names, options or "collaborators". End a refactor with "No behaviour change". Use the bare PR URL, with no `< >` around it or any other text; Slack unfurls it.

```
[`fort-knox`] Bureau reporting cleanup: quarantine and preview tests can now swap in fakes instead of stubbing globals. No behaviour change https://github.com/wealthsimple/fort-knox/pull/35439
```

## 5. Report CI

When the watch ends, say plainly that CI passed, or name each failed check with its link. A failure in a test that passed locally and touches nothing the PR changed is a likely flake: say so and suggest a rerun. Fixing failures is `babysit-pr`'s job; point there.

Done when the user has the post and the CI result.
