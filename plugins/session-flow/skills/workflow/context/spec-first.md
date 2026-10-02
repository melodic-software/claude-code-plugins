# Spec-first workflow (context-budget-aware)

Alternative execution mode for the staged workflow. Instead of running every stage in ONE long
session, where every turn re-processes the growing conversation, each stage persists its output to
disk, so the next stage can work from that artifact.

**Why:** long sessions compound per-turn token cost and invite context rot; an artifact on disk lets
each stage boundary carry on by whichever continuation fits without losing the stage's output.

**When to use:** multi-phase features spanning hours, work known in advance to have distinct
explore + research + plan + implement stages, cross-session work that may pause overnight.

**When NOT to use:** one-line fixes, quick config tweaks, tightly-coupled
exploration+implementation (e.g. debugging where findings shape the fix in real time). The default
is still the single-session pattern; spec-first is opt-in.

## How stage handoffs work

Each stage writes its output to the repo's work-artifact location (the consuming repo's documented
convention, or the topic's memory-tier slice `<memory_dir>/<slug>/` (default `.work/`); see the workflow skill's "Consumer
conventions"); `/session-flow:handoff` save-points land in the handoff skill's own home (`.work/handoffs/` by
default). The next stage reads only that artifact.

| Stage | Writes | Next stage reads |
|-------|--------|------------------|
| 0 Contract | brief/plan file (goal, constraints, acceptance criteria) | contract for explore/research/plan |
| 1 Explore | exploration findings file | context for research |
| 2 Research | research findings file (cited sources) | evidence for plan |
| 3 Plan | plan file (phases + verification criteria), user-approved | roadmap for implement |
| any | `/session-flow:handoff` save-point | mid-task snapshot for the fresh session |

## Execution pattern

```text
contract   → writes the brief
explore    → writes findings
research   → writes cited evidence
plan       → writes the approved plan
implement  → ships code, commits per phase
test → review → verify → /session-flow:retro
```

At each arrow, route the continuation with the router in [`continuation.md`](continuation.md); it
names which stage boundaries stay in one session and which move to a fresh one.

## Why it saves context

A single-session workflow re-processes the entire growing conversation on every turn. By the
implement stage, each turn carries every explore finding, every research pass, every plan
iteration, even though implementation only needs the approved plan. Because each stage's output is
on disk, the next stage can work from the artifact rather than from the conversation that produced
it.

## Mid-stage continuation

Mid-stage, when quality degrades or the window fills, route the continuation with
[`continuation.md`](continuation.md) too. When it routes to `/session-flow:handoff`, that skill owns
which sections a save-point carries. Multiple save-points accumulate; timestamps keep them ordered.

## Trade-offs

**Wins:** fewer tokens re-processed per stage, cleaner model focus, resilience to compaction,
cross-session resumability.

**Costs:** slight overhead writing + reading artifacts; stages must be artifact-complete (anything
left implicit in conversation is lost to the next stage).
