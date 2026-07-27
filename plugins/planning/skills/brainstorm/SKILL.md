---
name: brainstorm
description: "Diverge before scoping — turn a rough engineering/product problem into codebase-grounded candidate approaches ordered cheapest→most ambitious, capture which resonate, and hand off scoped. Use for 'brainstorm', 'what are my options', 'places we could intervene', 'how could we approach X', or any rough technical problem with no locked scope; skip when scope is already locked or the options are visual variations."
argument-hint: "<rough-problem> (e.g., /planning:brainstorm users churn after onboarding)"
user-invocable: true
disable-model-invocation: false
metadata:
  cheatsheet-stage: contract
  cheatsheet-summary: Diverge into codebase-grounded candidate approaches before scoping
---

## Purpose

The divergence step before any scoping: unknown-knowns (criteria the user only recognizes when seen) surface cheapest at candidate-list time — finding one mid-implementation costs a re-plan. A brainstorm round also calibrates scope: reacting to a cheapest→most-ambitious spread prevents locking a scope that is too narrow (missed the high-value approach) or too wide (ambition the problem doesn't need).

Distinct neighbors: `/design` Phase 1 decomposes the problem space WITHIN a design task already chosen; a proactive architecture-friction scan (e.g. `/architecture:improve`, if installed) hunts on its own lanes; a UI-variation prototyper (e.g. `/prototype:explore-directions`, if installed) builds visual variations of a chosen direction. This skill is the general, problem-shaped entry upstream of all three. Creative-domain ideation owned by a domain skill (e.g. songwriting brainstorms → `/songwriting:workflow`, if installed) stays with that skill.

## Task

Rough problem: $ARGUMENTS (if empty, infer from conversation; if nothing rough is open, say so and stop).

1. **Intake** — restate the problem in one sentence; if the user's starting point is unknown, ask ONE question to establish where they are — this is divergence, not an interview.
2. **Ground** — fast breadth pass (`Glob`/`Grep`/targeted Read — survey the file landscape before reading anything in depth) over where the problem lives: entry points, existing mechanisms that already partially address it, prior art in the repo.
3. **Diverge** — generate the candidate list (default ~10; scale to the problem), ordered **cheapest → most ambitious**. Every candidate is codebase-grounded — names the files/mechanisms it would touch — one line each: what, where, effort tier, expected impact. Do not self-censor the ambitious end; the user calibrates, not you.
4. **React** — the user marks what resonates. A prose numbered list is the default reaction surface; for a large or multi-axis spread, offer a self-contained HTML reaction-capture page (checkable candidates + a copy-out of the selection) as an ephemeral aid — the conversation record stays authoritative.
5. **Calibrate and hand off** — from the resonating candidates, propose a scope and route onward: `/prd` (product intent still fuzzy), `/interview` (engineering contract), `/design` (type/module decisions), or a feasibility/visual spike (`/prototype:pressure-test` / `/prototype:explore-directions` if installed; otherwise a throwaway spike you write and discard). State the recommended route with its basis, marked (RECOMMENDED).

## Output

Session output — no persisted artifact by default (ideation is conversation output, and divergence usually precedes the work having a home). When a topic slice already exists for the effort, offer to persist the candidate list + reactions to the topic's memory slice as `<memory_dir>/<topic-slug>/brainstorm.md` (default `.work/`) — opt-in only, never a default write, never the contract slice (roots resolve per [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)).

## What this skill does NOT do

- **Does not decide** — user reactions drive selection; the skill recommends, marked (RECOMMENDED) with basis
- **Does not lock scope or contract** — `/interview`
- **Does not explore the design space of a chosen direction** — `/design`
- **Does not build variations or throwaway code** — a prototyping capability (`/prototype:pressure-test` / `/prototype:explore-directions` when installed)
