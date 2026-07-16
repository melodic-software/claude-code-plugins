---
name: decompose
description: "Break a plan, spec, or PRD into independently-grabbable work items using vertical-slice (tracer-bullet) decomposition, with HITL/AFK classification and dependency ordering. Use when: 'decompose', 'break a plan into tickets', 'decompose into tickets', 'create issues from plan', 'decompose this PRD', 'split this plan into work items', 'turn the plan into tickets', 'vertical-slice this plan'. Reads a PLAN.md / PRD.md / item body / conversation, drafts thin end-to-end slices, classifies each AFK (agent-ready) vs HITL (needs-human), gets approval, then publishes blockers-first via the seam with native dependency edges. Sibling skills: /work-items:track (backlog CRUD), /work-items:work (auto-select + execute), /work-items:triage (raw intake), /work-items:scan (TODO sweep)."
argument-hint: "[source] — empty = topic PLAN.md; prd = topic PRD.md; #<number> = item body; or conversation context"
user-invocable: true
disable-model-invocation: false
---

## Variables

Arguments: `$ARGUMENTS`

## Shared tracker context

The seam, operation routing, label taxonomy, canonical-role remapping, recurring schedule, and
topic-docs binding that every work-items skill relies on live in
[`${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md)
(and the references it links). Read it at the start of an invocation. Item creation goes through the
seam `create-item` verb; the core inlines no provider commands.

## Purpose

Break a plan, spec, or PRD into independently-grabbable work items using vertical-slice (tracer-bullet) decomposition.

## Usage

```
/work-items:decompose [source]
```

`source` can be:

- *(empty)* — reads the topic's `PLAN.md` phases (default). Resolve the file per [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md): select the tier from the concern file's `contract_tier` FIRST — `branch` (default) → `<contract_dir>/<slug>/PLAN.md` (default `docs/topics/`); `local` → `<memory_dir>/<slug>/PLAN.md` (default `.work/`). The tier selects the location; never read the other tier's slice (a stale branch-tier slice must not shadow the live local one, or vice versa)
- `prd` — reads the topic's `PRD.md` user stories, resolved via the same tier-selected lookup
- `#<item-number>` — reads an existing item's body
- Conversation context — synthesizes from current discussion

## Process

### 1. Gather source material

Read the source document (PLAN.md/PRD.md located per the tier-selected lookup above — the configured tier's location only, never mix locations for one topic). If PLAN.md, extract phases + sanity checks. If PRD.md, extract user stories + goals. If an item, fetch full body and comments.

Use the project's domain glossary vocabulary throughout (its ubiquitous-language / glossary files when present). Respect the project's architecture decision records in the area.

### 2. Draft vertical slices

Break into **tracer-bullet** items. Each item is a thin vertical slice cutting through ALL integration layers end-to-end — NOT a horizontal slice of one layer.

**Vertical-slice rules:**

- Each slice delivers a narrow but COMPLETE path through every layer (domain, application, infrastructure, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
- Slices map to PLAN.md phases when source is a plan — but split phases that touch multiple independent concerns

**Classify each slice:**

| Type | Meaning | Role → label |
|------|---------|--------------|
| **AFK** | Implementable and mergeable without human interaction | autonomous-eligible (default `agent-ready`) |
| **HITL** | Requires human decision, design review, or manual testing | human-gated (default `needs-human`) |

Prefer AFK. Mark HITL only when the slice genuinely needs judgment (architectural decision, UX review, external-system access, manual QA). Both are canonical roles — resolve each repo-actual label string from the binding's `config.role_labels`, defaulting to the strings shown ([`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md) "Canonical roles").

The human-gated label (default `needs-human`) is what keeps a slice out of autonomous pickup — `list-frontier --autonomous` excludes it (`${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md` "Verbs (core public surface)"). Merely omitting the autonomous-eligible label does NOT: the frontier filter keys on the human-gated label, not on the absence of the other, so an unlabeled HITL slice would still be claimable by `/work-items:work`. The autonomous-eligible label (default `agent-ready`) is the positive autonomous-pickup eligibility marker; the two labels gate different filters and an HITL slice wants the human-gated label set AND the autonomous-eligible one omitted.

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

For each approved slice, create a work item via the seam (`${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh create-item`; `/work-items:track add` is the canonical creation path). **Publish in dependency order** — blockers first — so real IDs can fill the `--blocked-by` edges of dependents (native dependency edges, not just body text):

```bash
# AFK slices get the autonomous-eligible role label; HITL + investigation slices get the
# human-gated one — the label list-frontier --autonomous actually honors to exclude an item.
# Omitting the autonomous-eligible label alone does NOT keep an HITL slice off the frontier.
# Defaults shown; substitute the binding's config.role_labels values when the repo remaps.
META_LABEL=$([ -n "$AFK" ] && echo "agent-ready" || echo "needs-human")
BODY_FILE=$(mktemp)
# Write the composed slice body to "$BODY_FILE" with the Write tool NOW — before create-item —
# not via shell interpolation. plan/PRD text can contain backticks or $() the shell would
# interpret; "$(cat "$BODY_FILE")" passes it as one literal argument, never re-parsed.
# --type: org repos only (native Issue Type); on personal/non-org repos drop --type and prepend a coarse type: bug|feature|task label to --labels instead
TRACKER="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/tools/work-item-tracker/work-item-tracker.sh}"
[[ -f "$TRACKER" ]] || TRACKER="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/work-item-tracker.sh"
"$TRACKER" create-item --title "<slice title>" --body "$(cat "$BODY_FILE")" \
  --type "<Bug|Feature|Task>" \
  --labels "area: <a>,$META_LABEL" \
  --blocked-by "<blocker-id>[,<blocker-id>]"
rm -f "$BODY_FILE"
```

Use agent-brief body format (see [`${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md)) for AFK slices. Body structure:

```markdown
## Parent

Refs #<parent-item> (if source was an existing item)
<!-- or: Source: <contract_dir>/<slug>/PLAN.md Phase N (write the resolved path) -->

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

Classify per taxonomy: the **issue type** from the slice nature — `Bug` (fixing broken behavior), `Feature` (new capability), `Task` (everything else) — set through the seam's `--type` on org repos (native Issue Type), or a `type:` label on personal / non-org repos; `area:` from the affected module; the autonomous-eligible label for AFK slices, the human-gated label for HITL + investigation slices. The seam records `--blocked-by` as a native dependency edge; the human-readable "Blocked by" body section mirrors it for readers.

Items published here are **born triaged**: they enter the tracker classified, role-labeled, and briefed at creation, so `/work-items:triage` never re-processes them.

**Do NOT close or modify any parent item** — decomposition creates children, doesn't replace the parent.

### 5. Report

After publishing, present summary: N items created, dependency graph, which are AFK vs HITL, suggested execution order.
