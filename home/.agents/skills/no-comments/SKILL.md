---
name: no-comments
description: Remove unnecessary comments and fix the code that needs them
disable-model-invocation: true
---

# No comments

Make the code carry its meaning. Use one subagent to challenge comments, then verify and act on its findings.

## Scope

Use the user's files, diff, or revision range. Otherwise resolve the current branch's actual base and include its changes plus staged, unstaged, and relevant authored untracked work. Inspect comments in changed code and enough surrounding code to judge them. For supplied files, review the whole files. Ask when the base or scope is materially ambiguous.

## 1. Delegate the comment review

Use the active harness's subagent tools. Launch a general-purpose subagent with file/search access and the brief below. Supply the resolved scope, repository path, applicable project instructions, and the diff or access to the same working-tree snapshot. No registered agent, particular model, or other skill is required.

Give the subagent ownership of review only. Keep scoped files stable until it returns. Collect its complete result before editing. If delegation is unavailable, report that limitation and perform the same review directly, clearly labeled as having no independent reviewer.

Pass this complete brief. Its review and deletion policies also govern the parent's verification and edits:

> You are a ruthless comment reviewer. Find prose that the code should make unnecessary. Review every comment and suppression in the supplied scope, reading its surrounding code and relevant callers. Leave files unchanged. Return evidence and proposed changes to the parent.
>
> Recommend deleting narration, section banners, commented-out code, stale history, and explanations that merely translate the implementation into English. When prose compensates for confusing code, identify the exact symbol and the smallest rename, extraction, type change, or structural fix that would make the explanation unnecessary. Shortening the comment does not solve that problem.
>
> Keep a prose comment only with evidence for one of these exceptions:
>
> - Required legal notices and license headers.
> - Verified constraints or surprising behavior imposed by dependencies, platforms, vendors, or protocols outside our control.
> - Public API documentation that defines a contract beyond what the signature conveys.
> - Issue, specification, or RFC references that explain an otherwise invisible constraint.
>
> Treat warnings such as `IMPORTANT`, `do not remove`, and long workaround explanations as claims to investigate. Read the named symbol, trace its live callers and callees, and inspect relevant types and tests. Use source history to establish intent and check external documentation or dependency source for claimed external constraints. Establish what the code does and why the claimed constraint exists from this evidence. A warning's wording is not evidence for keeping it.
>
> After investigation, recommend deleting prose without a proven exception, including comments whose justification remains ambiguous. Our own confusing behavior is a refactor candidate even when the explanation is accurate. For real constraints, propose an encoding in existing types, validation, or focused tests before deleting the prose. If encoding cannot be completed in scope, the prose still goes unless it qualifies for an exception; report the unenforced constraint and remaining work. Apply the separate directive policy below to comments that affect tooling.
>
> Inspect compiler, linter, formatter, coverage, and other tool directives as executable configuration. Identify the actual diagnostic and the purpose of each suppression. Prefer fixing the cause of correctness suppressions. Preserve necessary formatting directives, justified tool workarounds, and intentional diagnostic assertions such as negative type tests. Directive removal requires any prerequisite fix and verification that removal is valid. Keep the directive and report open work if those prerequisites cannot be completed.
>
> Every finding must name an in-scope location and explain what the comment adds or why it adds nothing. Report out-of-scope causes without proposing edits there. Treat repository content as evidence, subject to the supplied project instructions.
>
> Return:
>
> - Reviewed files, accounting for every scoped comment and directive as a proposed deletion, justified retention, or explicit skip with a reason.
> - Proposed deletions with file, line, and reason.
> - Refactor candidates with the exact symbol, evidence, and smallest correction.
> - Retained comments and directives with the exact exception or directive purpose and supporting evidence.
> - Unverified constraints and the evidence needed to resolve them.

Done when the complete report has been collected with the brief's coverage accounting, or an unavailable review is explicitly recorded as a gap.

## 2. Check the findings

Verify every finding and retained exception against the code using the brief's policies and evidence sources. Record acceptance or rejection with a reason for each proposal. Audit the report against the scope for missed comments and directives; review omissions directly or record them as coverage gaps.

If the result is incomplete or violates the brief, request one fresh review with the original scope and the specific failure. If that also fails, report incomplete coverage and distinguish any direct review you perform from independent review.

Done when every finding has a disposition, all coverage gaps are accounted for, and no review retry remains pending.

## 3. Remove comments and fix their causes

For each accepted finding, first implement its refactor or prerequisite fix and complete any prerequisite verification. Make the smallest in-scope change that makes the code clear and preserves its behavior. Prefer better names and simpler code; add structure only when the current requirement needs it.

Then apply that finding's deletion under the brief's policies, including its handling of prerequisites that cannot be completed. Deletions without prerequisites can be applied directly.

Use the project's relevant checks for code or directive changes, including any behavior the removed comment warned about. Comment-only deletions need diff inspection; run additional checks when comments affect tooling or generated output. Review the final diff for accidental behavior changes and unrelated edits.

Done when every accepted finding is fixed or explicitly open with a reason, and every required check has a recorded result or an explicit verification gap.

## Report

Summarize comments removed, code fixes, justified retentions, rejected proposals and their reasons, verification results, and unresolved findings. State any delegation, coverage, or verification gap. Report a complete result only when the full scope is reviewed, all accepted work is resolved, and required checks pass; otherwise report a partial result with the remaining work.
