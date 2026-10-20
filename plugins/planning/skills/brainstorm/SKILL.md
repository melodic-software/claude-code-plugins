---
description: "Diverge before scoping: turn a rough engineering/product problem into codebase-grounded candidate approaches, cheapest→most ambitious, capture which resonate, and hand off scoped. Use when: 'brainstorm', 'what are my options', 'places we could intervene', 'how could we approach X', 'ideas for this', 'explore some approaches', 'what could we do here', or any rough technical problem with no locked scope; skip when scope is already locked or the options are visual variations."
argument-hint: "<rough-problem>"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: contract
  summary: Diverge into codebase-grounded candidate approaches before scoping
---

**Arguments.** `<rough-problem>`. e.g., /planning:brainstorm users churn after onboarding

## Purpose

The divergence step before any scoping: unknown-knowns (criteria the user only recognizes when seen)
surface cheapest at candidate-list time. Finding one mid-implementation costs a re-plan. A
cheapest→most-ambitious spread also calibrates scope: neither too narrow (missed the high-value
approach) nor too wide (ambition the problem doesn't need).

Opening a fresh session on a rough problem with a brainstorm is a citable practice, not a detour:
the cheapest→ambitious spread is the cheapest artifact that surfaces criteria the user only
recognizes when seen (rationale and sources: `docs/finding-your-unknowns.md` in the marketplace
repository).

Distinct neighbors: `/planning:design` Phase 1 decomposes the problem space WITHIN a design task
already chosen; a proactive architecture-friction scan (e.g. `/architecture:improve`, if enabled)
hunts on its own lanes; a UI-variation prototyper (e.g. `/prototype:explore-directions`, if
enabled) builds visual variations of a chosen direction. This skill is the general, problem-shaped
entry upstream of all three. One request to raise or deepen, not options to compare, is
`/discipline:be-ambitious` (if enabled; the user types it). Creative-domain ideation owned by a domain skill (e.g. songwriting
brainstorms → `/songwriting:workflow`, if enabled) stays with that skill.

## Task

Rough problem: $ARGUMENTS (if empty, infer from conversation; if nothing rough is open, say so and
stop).

1. **Intake**. Restate the problem in one sentence; if the user's starting point is unknown, ask
   ONE question to establish where they are. This is divergence, not an interview.
2. **Ground**. Fast breadth pass (`Glob`/`Grep`/targeted Read; survey the file landscape before
   reading anything in depth) over where the problem lives: entry points, existing mechanisms that
   already partially address it, prior art in the repo.
   Before any candidate, read the Brief's `### Problem`; absent, establish it (problem fields, evidence
   rating, restate-and-confirm; a prescribed solution gets rethink-or-accept):
   [`${CLAUDE_PLUGIN_ROOT}/context/problem-framing.md`](../../context/problem-framing.md). Its
   `time_units` user layer is `${user_config.time_units}` (unexpanded means unset).
3. **Diverge**. Generate the candidate list (default ~10; scale to the problem), ordered
   **cheapest → most ambitious**. Every candidate is codebase-grounded and names the
   files/mechanisms it would touch, one line each: what, where, effort tier (a `work_size` size level), expected impact. Do
   not self-censor the ambitious end; the user calibrates, not you.
4. **React**. The user marks what resonates. A prose numbered list is the default reaction
   surface; for a large or multi-axis spread, offer an interactive view (candidates from cheapest to
   most ambitious, a tick for each that resonates, a copy-out of the reaction, sent to this session
   through `session-bridge` when connected; the session's reply shows on the page, and a sent
   reaction is data that locks no scope). Never write the page into the memory slice, even when the
   user opts into persisting `brainstorm.md` there; the conversation record stays authoritative.
   Build it only with `${CLAUDE_PLUGIN_ROOT}/scripts/build-view.mjs`, never hand-written; the
   publish destination comes from the `medium` cascade key. Procedure and data shape:
   [`${CLAUDE_PLUGIN_ROOT}/reference/rendered-view.md`](${CLAUDE_PLUGIN_ROOT}/reference/rendered-view.md).
5. **Calibrate and hand off**. From the resonating candidates, propose a scope and route onward:
   `/planning:prd` (product intent still fuzzy), `/planning:interview` (engineering contract),
   `/planning:design` (type/module decisions), or a feasibility/visual spike
   (`/prototype:pressure-test` / `/prototype:explore-directions` if enabled; otherwise a throwaway
   spike you write and discard). Mark the recommended route (RECOMMENDED), with a `Basis:` line:
   `verified` with the `file:line`, tool output, or URL it rests on, or `judgment`
   (non-consequential only). Ground a consequential recommendation (cross-repo, shared
   infrastructure, irreversible, or security) in its consumers and in external research before
   presenting it; when research cannot settle it, withhold the recommendation and name the open
   question and the evidence that would settle it. Contract:
   [`${CLAUDE_PLUGIN_ROOT}/context/recommendation-basis.md`](../../context/recommendation-basis.md).

## Output

No persisted artifact by default (ideation is conversation output, and divergence usually precedes
the work having a home). When a topic slice already exists for the effort, offer to
persist the candidate list + reactions as `<memory_dir>/<topic-slug>/brainstorm.md` (default
`.work/`). Opt-in only, never a default write (placement per
[`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md)).

## Next

- An approach resonates and the engineering contract is next: /planning:interview.
- Product intent: /planning:prd.
- Type and module decisions: /planning:design.
- Unsure where this leaves the work, or arrived mid-flow: /session-flow:workflow.

## What this skill does NOT do

- **Does not decide**. User reactions drive selection; the skill recommends, marked (RECOMMENDED)
  with basis
- **Does not lock scope or contract**. `/planning:interview`
- **Does not explore the design space of a chosen direction**. `/planning:design`
- **Does not build variations or throwaway code**. A prototyping capability
  (`/prototype:pressure-test` / `/prototype:explore-directions` when enabled)
