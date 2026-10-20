---
description: "Diverge before scoping: turn a rough engineering/product problem into codebase-grounded candidate approaches, cheapest→most ambitious, capture which resonate, and hand off scoped. Use when: 'brainstorm', 'what are my options', 'places we could intervene', 'how could we approach X', 'ideas for this', 'explore some approaches', 'what could we do here', or any rough technical problem with no locked scope; skip when scope is already locked or the options are visual variations."
argument-hint: "<rough-problem>"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: prd
  summary: Diverge into codebase-grounded candidate approaches before scoping
---

**Arguments.** `<rough-problem>`. e.g., /planning:brainstorm users churn after onboarding

## Purpose

The divergence step before any scoping: unknown-knowns (criteria the user only recognizes when seen)
surface cheapest at candidate-list time. Finding one mid-implementation costs a re-plan. A
cheapest→most-ambitious spread also calibrates scope: neither too narrow (missed the high-value
approach) nor too wide (ambition the problem doesn't need). It is also where a half-formed idea
goes: the run settles the problem and the user's intent, and hands both forward.

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

The run follows
[`${CLAUDE_PLUGIN_ROOT}/context/problem-framing.md`](../../context/problem-framing.md) "Idea-stage
requests". Its `time_units` user layer is `${user_config.time_units}` (unexpanded means unset).

1. **Intake: problem and intent.** Read the Brief's `### Problem` when one exists; otherwise state
   the problem in one line with no solution in it, its evidence rated per "Evidence rating". In one
   message, skipping any question the request already answers, ask:
   - Is that the problem? (yes, or a correction; a correction restates again)
   - Why does it matter to you, and where do you want this to head? Keep both in the user's words.
   - What ideas do you already have, however rough? Ask before showing any candidate, so the user
     stays the author of the direction: ideas the agent writes for the user lower the user's
     ownership of them. Keep the user's wording for their ideas.

   A solution the user named is one of their ideas; one question may ask whether to rethink it or
   keep it. Beyond these, ask at most ONE question, only to learn where the user is starting from.
   Propose no approach of your own until the user answers. If the user asks to skip the questions,
   restate the problem, record the intent as `not stated`, and go on.
2. **Ground**. Fast breadth pass (`Glob`/`Grep`/targeted Read; survey the file landscape before
   reading anything in depth) over where the problem lives: entry points, existing mechanisms that
   already partially address it, prior art in the repo. Optional landscape pass, when it would
   change the candidates: `/discovery:research` for how others solve this problem,
   `/discovery:blindspot` when the domain is unfamiliar to the user, `/discovery:explore` for a
   deeper codebase map than the breadth pass gives.
3. **Diverge**. Generate the candidate list (default ~10; scale to the problem), ordered
   **cheapest → most ambitious**. Each of the user's ideas is a candidate, in their words, marked
   as theirs. Candidates span kinds of fix, not variants of one: besides code changes, a process
   change, buying or configuring an existing tool, or doing nothing, each labeled `non-code`. A
   code candidate names the files/mechanisms it would touch; a non-code one names what it changes
   instead. One line each: what, where, effort tier, expected impact. The effort tier is a
   `work_size` size level that only orders the list: it carries no split meaning, and "Large size"
   does not apply to a candidate. Do not self-censor the ambitious end; the user calibrates, not
   you.
4. **React**. The user marks what resonates. For each pick, ask why it resonates unless the user
   said, and record the reasons as criteria (what the user values, such as "no new service to
   run"); record why a dropped candidate lost when the user says. A prose numbered list is the
   default reaction surface; for a large or multi-axis spread, offer an interactive view
   (candidates from cheapest to most ambitious, a tick for each that resonates, a copy-out of the
   reaction, sent to this session when connected per
   [`${CLAUDE_PLUGIN_ROOT}/reference/rendered-view.md`](${CLAUDE_PLUGIN_ROOT}/reference/rendered-view.md)
   "Connect a view to the session"; the session's reply shows on the page, and a sent reaction is
   data that locks no scope). Never write the page into the memory slice; the conversation record
   stays authoritative. Build it only with `${CLAUDE_PLUGIN_ROOT}/scripts/build-view.mjs`, never
   hand-written; the publish destination comes from the `medium` cascade key. Procedure and data
   shape: the same rendered-view reference.
5. **Calibrate and hand off**. From the resonating candidates and the criteria, propose a scope and
   route onward: `/planning:prd` (product intent still fuzzy), `/planning:interview` (engineering
   contract), `/planning:design` (type/module decisions), or a feasibility/visual spike through
   `/prototype:pressure-test` or `/prototype:explore-directions` when enabled. Mark the recommended
   route (RECOMMENDED), with a `Basis:` line:
   `verified` with the `file:line`, tool output, or URL it rests on, or `judgment`
   (non-consequential only). Ground a consequential recommendation (cross-repo, shared
   infrastructure, irreversible, or security) in its consumers and in external research before
   presenting it; when research cannot settle it, withhold the recommendation and name the open
   question and the evidence that would settle it. Contract:
   [`${CLAUDE_PLUGIN_ROOT}/context/recommendation-basis.md`](../../context/recommendation-basis.md).
   On a route to `/planning:interview`, `/planning:prd` or `/planning:design`, write the handoff
   block (Output) and name its path in the route.

## Output

On a route to `/planning:interview`, `/planning:prd` or `/planning:design`, write
`<memory_dir>/<topic-slug>/brainstorm.md` (default `.work/`; the existing slice for the effort, else
a slug from the problem; placement per
[`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md))
holding this block, every field filled or `not stated`:

```markdown
## Handoff

- Problem: <the confirmed one-line problem, evidence rated>
- Intent (why, in the user's words): <the user's words>
- Vision (where this heads): <the user's words>
- Chosen direction: <the resonating candidates and the proposed scope>
- Rejected options: <each candidate not chosen, with its reason>
- Criteria surfaced: <why each chosen candidate resonated>
```

The full candidate list and reactions go into the same file only when the user opts in. Other
routes write nothing.

## Next

- The engineering contract is next, carrying the handoff block: /planning:interview.
- Product intent is still fuzzy: /planning:prd.
- Type and module decisions: /planning:design.
- Unsure where this leaves the work, or arrived mid-flow: /session-flow:workflow.

## What this skill does NOT do

- **Does not decide**. User reactions drive selection; the skill recommends, marked (RECOMMENDED)
  with basis
- **Does not lock scope or contract**. `/planning:interview`
- **Does not explore the design space of a chosen direction**. `/planning:design`
- **Does not build variations or throwaway code**. A prototyping capability
  (`/prototype:pressure-test` / `/prototype:explore-directions` when enabled)
