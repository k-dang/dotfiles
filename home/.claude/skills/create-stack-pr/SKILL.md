---
description: Create a Graphite stack PR with guided commit message
allowed-tools: Bash(gt:*), Bash(git status:*), Bash(git diff:*), Bash(echo:*), Bash(fold:*), Bash(wc:*)
argument-hint: [motivation/context]
---

## User-Provided Context

$ARGUMENTS

## Git Context

Current git status:
!`git status --short`

Staged changes (if any):
!`git diff --cached`

Unstaged changes (if nothing staged):
!`git diff`

## Your Task

Help me create a commit and submit it as a Graphite stack PR.

**IMPORTANT:** Always use Graphite (`gt`) commands - never bypass with raw git commands like `git commit`, `git push`, or `git checkout -b`. Graphite manages the stack state and using git directly will corrupt it.

### Step 1: Analyze the Changes

Study the diff above to understand:
- What files were modified and why
- The nature of the change (bug fix, new feature, refactor, etc.)
- The scope and impact of the changes

### Step 2: Gather Context

**If user provided context above:** Use it as the motivation/explanation. Only ask follow-up questions if something critical is still unclear.

**If no context provided:** Ask targeted questions to understand the change. Don't use a fixed checklist - be intelligent about what's missing:
- If the change is obvious from the code, just confirm your understanding
- If the "why" isn't clear from the diff, ask about motivation
- If there might be side effects, ask about them
- If the change type is ambiguous, ask for clarification

The goal is a conversation, not an interrogation.

### Step 3: Generate Commit Message

Create a commit message following these rules:

**Subject line:**
- Maximum 50 characters (verify with `echo -n "subject" | wc -c`)
- Imperative mood (e.g., "Fix bug" not "Fixed bug")

**Body:**
- Blank line after subject
- Wrapped at 72 characters (use `echo "body text" | fold -s -w 72`)
- Focus on the "why", not the "what" - the diff already shows what changed
- Don't list affected files/classes/functions - that's redundant with the diff
- Should answer: why is this change necessary, what problem does it solve

### Step 4: Generate Branch Name

Create a short kebab-case branch name:
- Simple slug format (e.g., `fix-null-pointer`, `add-user-validation`, `update-deps`)
- Lowercase, hyphens between words
- No type prefix, just a descriptive slug

### Step 5: Create the Branch and Commit

Show me the proposed commit message and branch name. Once I approve, run:
```bash
gt create --all --no-interactive -m "$(cat <<'EOF'
<subject line here>

<wrapped body here>
EOF
)" <branch-name>
```

### Step 6: Submit the PR

Submit the PR as a draft:

```bash
gt stack submit --no-interactive --draft
```

### Step 7: Output Slack Review Message

Output both Slack-friendly message formats in a fenced markdown block for easy copy-paste:

```
Single PR:
[<commit subject>](<github-url>) ([graphite](<graphite-url>))

Stack:
[<top PR title>](<graphite-stack-url>)
```

Print the actual links (not placeholders) so they can be copied directly into Slack.
