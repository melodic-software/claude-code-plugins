# Action: `decompose`

Break a plan, spec, or PRD into independently-grabbable issues using vertical-slice (tracer-bullet) decomposition.

## Usage

```
decompose [source]
```

`source` can be:

- *(empty)* — reads the consuming project's current plan document (its planning convention's output, e.g. a PLAN.md in the active working notes) — ask which document when ambiguous
- A path — reads that plan/PRD document directly
- `#<issue-number>` — reads an existing issue's body
- Conversation context — synthesizes from current discussion

## Process

### 1. Gather source material

Read the source document. If a plan, extract phases + verification criteria. If a PRD, extract user stories + goals. If an issue, fetch full body and comments.

Use the project's domain glossary vocabulary throughout (its ubiquitous-language / glossary files when present). Respect the project's architecture decision records in the area.

### 2. Draft vertical slices

Break into **tracer-bullet** issues. Each issue is a thin vertical slice cutting through ALL integration layers end-to-end — NOT a horizontal slice of one layer.

**Vertical-slice rules:**

- Each slice delivers a narrow but COMPLETE path through every layer (domain, application, infrastructure, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
- Slices map to plan phases when source is a plan — but split phases that touch multiple independent concerns

**Classify each slice:**

| Type | Meaning | Label |
|------|---------|-------|
| **AFK** | Implementable and mergeable without human interaction | `agent-ready` |
| **HITL** | Requires human decision, design review, or manual testing | No `agent-ready` label |

Prefer AFK. Mark HITL only when the slice genuinely needs judgment (architectural decision, UX review, external-system access, manual QA).

### 3. Present for approval

Present the proposed breakdown as a numbered list. For each slice:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (by number) must complete first
- **User stories covered**: which user stories this addresses (if PRD source)
- **Estimated scope**: S / M / L

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are dependency relationships correct?
- Should any slices be merged or split?
- Are HITL/AFK classifications correct?

Iterate one question at a time until the user approves — never publish an unapproved breakdown.

### 4. Publish issues

For each approved slice, create an issue (the `add` action is the canonical creation path). **Publish in dependency order** — blockers first — so real issue numbers can be referenced in "Blocked by" fields.

Use the agent-brief body format ([`../reference/agent-brief.md`](../reference/agent-brief.md)) for AFK slices. Body structure:

```markdown
## Parent

Refs #<parent-issue> (if source was an existing issue)
<!-- or: Source: <plan document> Phase N -->

## What to build

Concise description of this vertical slice. Describe end-to-end behavior, not layer-by-layer implementation. No file paths — they go stale. Exception: if a prototype produced a snippet encoding a design decision more precisely than prose (state machine, reducer, schema, type shape), inline it and note it came from a prototype.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

- #<blocker-issue-number>

Or "None — can start immediately" if no blockers.
```

Apply labels per taxonomy: `type:` from slice nature, `area:` from affected module (when the repo defines area labels), `agent-ready` for AFK slices.

**Do NOT close or modify any parent issue** — decomposition creates children, doesn't replace the parent.

### 5. Report

After publishing, present summary: N issues created, dependency graph, which are AFK vs HITL, suggested execution order.
