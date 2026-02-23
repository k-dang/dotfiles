---
name: prd-to-issues
description: Breaks a PRD markdown file into independently-grabbable issues using vertical slices (tracer bullets), writing them to ISSUES.md. Use when the user wants to decompose a PRD into tickets, create issues from a spec, or plan implementation work as slices.
disable-model-invocation: true
---

# PRD to Issues

Break a PRD into independently-grabbable issues using vertical slices (tracer bullets).

## Process

### 1. Locate the PRD

Ask the user for the path to a PRD markdown file. Read it with the Read tool and internalize the full PRD content.

### 2. Explore the codebase

Read the key modules and integration layers referenced in the PRD. Identify:

- The distinct integration layers the feature touches (e.g. DB/schema, API/backend, UI, tests, config)
- Existing patterns for similar features
- Natural seams where work can be parallelized

### 3. Draft vertical slices

Break the PRD into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
- The first slice should be the simplest possible end-to-end path (the "hello world" tracer bullet)
- Later slices add breadth: edge cases, additional user stories, polish
</vertical-slice-rules>

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Layers touched**: which integration layers this slice cuts through
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories from the PRD this addresses

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Is the ordering right for the first tracer bullet?
- Are there any slices missing?

Iterate until the user approves the breakdown.

### 5. Write the issues markdown file

Write all approved slices to `ISSUES.md` in the current directory. Use the structure below.

Number issues sequentially starting from 1. Reference blockers by their number (e.g. `#1`).

<issues-file-template>
# Issues

## Summary

| # | Title | Blocked by | Status |
|---|-------|------------|--------|
| 1 | Basic widget creation | None | Ready |
| 2 | Widget listing | #1 | Blocked |

---

## Issue 1: <Title>

### What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation.

### Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

### Blocked by

None - can start immediately.

### User stories addressed

- User story 3
- User story 7

---

## Issue 2: <Title>

...
</issues-file-template>
