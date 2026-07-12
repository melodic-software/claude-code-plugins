# Action: `decompose`

Break a plan, spec, or PRD into independently-grabbable work items using vertical-slice (tracer-bullet) decomposition.

## Usage

```
/work-items decompose [source]
```

`source` can be:

- *(empty)* — reads `.work/<slug>/PLAN.md` phases (default)
- `prd` — reads `.work/<slug>/PRD.md` user stories
- `#<item-number>` — reads an existing item's body
- Conversation context — synthesizes from current discussion

## Process

### 1. Gather source material

Read the source document. If PLAN.md, extract phases + sanity checks. If PRD.md, extract user stories + goals. If an item, fetch full body and comments.

Use the project's domain glossary vocabulary throughout (its ubiquitous-language / glossary files when present). Respect the project's architecture decision records in the area.

### 2. Draft vertical slices

Break into **tracer-bullet** items. Each item is a thin vertical slice cutting through ALL integration layers end-to-end — NOT a horizontal slice of one layer.

**Vertical-slice rules:**

- Each slice delivers a narrow but COMPLETE path through every layer (domain, application, infrastructure, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
- Slices map to PLAN.md phases when source is a plan — but split phases that touch multiple independent concerns

**Classify each slice:**

| Type | Meaning | Label |
|------|---------|-------|
| **AFK** | Implementable and mergeable without human interaction | `agent-ready` |
| **HITL** | Requires human decision, design review, or manual testing | `needs-human` |

Prefer AFK. Mark HITL only when the slice genuinely needs judgment (architectural decision, UX review, external-system access, manual QA).

`needs-human` is the label that keeps a slice out of autonomous pickup — `list-frontier --autonomous` excludes it (`tools/work-item-tracker/CONTRACT.md` "Verbs (core public surface)"). Merely omitting `agent-ready` does NOT: the frontier filter keys on the `needs-human` label, not on the absence of `agent-ready`, so an unlabeled HITL slice would still be claimable by `/work-items work`. `agent-ready` is the positive autonomous-pickup eligibility marker; the two labels gate different filters and an HITL slice wants `needs-human` set AND `agent-ready` omitted.

**Investigation tickets — decisions, not deliverables.** When the source still carries unresolved unknowns (open design questions, unvalidated approaches, fuzzy scope), emit **investigation tickets** alongside — or ahead of — build slices. An investigation ticket resolves ONE decision and records the resolution as a closing comment; it produces no production code. Type each by the skill that resolves it:

| Investigation type | Resolves | Routes to |
|--------------------|----------|-----------|
| research | External unknown (best practice, library choice, API behavior) | `/research` |
| prototype | Feasibility or design-feel unknown | `/prototype` |
| interview | Scope/contract ambiguity only the user can settle | `/interview` |

Build slices blocked on an unresolved decision list the investigation ticket in "Blocked by". Investigation tickets are HITL by default (their output is a decision a human confirms) — label them `needs-human`, never `agent-ready`.

### 2b. Wide refactors — expand-contract exception

Mechanical changes with codebase-wide blast radius (rename a persisted column, retype a shared symbol, swap a serialization format) cannot land green as one vertical slice — a single-ticket attempt breaks every consumer at once. Sequence them **expand → migrate → contract**:

1. **Expand** — one ticket adds the new form beside the old; both work; lands green
2. **Migrate** — one ticket per consumer batch moves call sites to the new form; each batch lands green independently
3. **Contract** — one final ticket removes the old form once nothing references it

Each step is its own ticket with blocking edges (contract blocked by every migrate batch; migrate batches blocked by expand). Caveat: shared integration points (a wire format, a persisted schema) may pin expand + contract to a coordinated window — say so in the ticket body.

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

### 4. Publish items

For each approved slice, create a work item via the seam (`tools/work-item-tracker/work-item-tracker.sh create-item`; `/work-items add` is the canonical creation path). **Publish in dependency order** — blockers first — so real IDs can fill the `--blocked-by` edges of dependents (native dependency edges, not just body text):

```bash
# AFK slices get agent-ready (autonomous-pickup eligibility); HITL + investigation slices
# get needs-human instead — the label list-frontier --autonomous actually honors to exclude
# an item. Omitting agent-ready alone does NOT keep an HITL slice off the frontier.
META_LABEL=$([ -n "$AFK" ] && echo "agent-ready" || echo "needs-human")
tools/work-item-tracker/work-item-tracker.sh create-item --title "<slice title>" --body "<body>" \
  --labels "type:<t>,area:<a>,$META_LABEL" \
  --blocked-by "<blocker-id>[,<blocker-id>]"
```

Use agent-brief body format (see [`reference/agent-brief.md`](../reference/agent-brief.md)) for AFK slices. Body structure:

```markdown
## Parent

Refs #<parent-item> (if source was an existing item)
<!-- or: Source: .work/<slug>/PLAN.md Phase N -->

## What to build

Concise description of this vertical slice. Describe end-to-end behavior, not layer-by-layer implementation. No file paths — they go stale. Exception: if `/prototype:logic` produced a snippet encoding a design decision more precisely than prose (state machine, reducer, schema, type shape), inline it and note it came from a prototype.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

- #<blocker-item-number>

Or "None — can start immediately" if no blockers.
```

Apply labels per taxonomy: `type:` from slice nature, `area:` from affected module, `agent-ready` for AFK slices, `needs-human` for HITL + investigation slices. The seam records `--blocked-by` as a native dependency edge; the human-readable "Blocked by" body section mirrors it for readers.

**Do NOT close or modify any parent item** — decomposition creates children, doesn't replace the parent.

### 5. Report

After publishing, present summary: N items created, dependency graph, which are AFK vs HITL, suggested execution order.
