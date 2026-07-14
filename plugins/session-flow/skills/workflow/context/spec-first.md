# Spec-first workflow (context-budget-aware)

Alternative execution mode for the staged workflow. Instead of running every stage in ONE long
session — where every turn re-processes the growing conversation — each stage persists its output to
disk and the next stage starts fresh via `/clear`.

**Why:** long sessions compound per-turn token cost and invite context rot; clearing between stages
trades a small re-read cost for tight, purpose-built context per stage.

**When to use:** multi-phase features spanning hours, work known in advance to have distinct
explore + research + plan + implement stages, cross-session work that may pause overnight.

**When NOT to use:** one-line fixes, quick config tweaks, tightly-coupled
exploration+implementation (e.g. debugging where findings shape the fix in real time). The default
is still the single-session pattern — spec-first is opt-in.

## How stage handoffs work

Each stage writes its output to the repo's work-artifact location (the consuming repo's documented
convention, or the plugin default `.work/handoffs/` — see the workflow skill's "Consumer
conventions"). The next stage reads only that artifact.

| Stage | Writes | Next stage reads |
|-------|--------|------------------|
| 0 Contract | brief/plan file (goal, constraints, acceptance criteria) | contract for explore/research/plan |
| 1 Explore | exploration findings file | context for research |
| 2 Research | research findings file (cited sources) | evidence for plan |
| 3 Plan | plan file (phases + verification criteria), user-approved | roadmap for implement |
| any | `/handoff` save-point | mid-task snapshot for the fresh session |

## Execution pattern

```text
contract   → writes the brief                → /clear
explore    → writes findings                 → /clear
research   → writes cited evidence           → /clear
plan       → writes the approved plan        → /clear
implement  → ships code, commits per phase   → (optional /handoff if context bloats)
test → review → verify → /retro              ← the back half often runs in one session
```

`/clear` between every stage is the maximum-reduction pattern. In practice, collapse adjacent
stages when context is still small — but commit to clearing at least between research and plan, and
between plan and implement. Those are the biggest re-processing wins.

## Why it saves context

A single-session workflow re-processes the entire growing conversation on every turn. By the
implement stage, each turn carries every explore finding, every research pass, every plan
iteration — even though implementation only needs the approved plan. With `/clear` between stages,
each stage's context is tight and purpose-built, and compaction is rarely reached.

## /handoff: the escape hatch

Mid-stage, if context grows heavy or quality degrades, invoke `/handoff` to snapshot the current
state (what's done, decisions, what was tried and ruled out, next steps) and `/clear`. Multiple
save-points accumulate; timestamps keep them ordered.

## Trade-offs

**Wins:** fewer tokens re-processed per stage, cleaner model focus, resilience to compaction,
cross-session resumability.

**Costs:** slight overhead writing + reading artifacts; stages must be artifact-complete (anything
left implicit in conversation is lost to the next stage); over-clearing on tiny tasks is noise.
