---
name: research-deep
description: "Dispatch deep external research to the heaviest isolated execution tier available — a workflow engine, a forked subagent, or inline as last resort — keeping the main conversation clean while the full research discipline runs. Itself runs in main context, because a subagent cannot reach the Workflow tool. Use when: 'deep research', 'research these N topics', 'broad multi-source research', 'compare these tools thoroughly', 'migration research', 'exhaustive research on X'; for a single small lookup use the research skill directly, which already dispatches its own subagent."
argument-hint: "[topic] (e.g., /discovery:research-deep <library> <version> best practices, /discovery:research-deep <framework> <feature> migration guide)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

`/research-deep` is the **dispatcher** for deep external research — a depth/execution variant of the sibling `/research` skill. Same research contract (3-phase discipline, source-tier ratio, recency gate, mandatory falsification, cited `RESEARCH.md` artifact); heavier execution that keeps the main session's context clean. It selects ONE execution tier from tool availability + task heaviness, then surfaces the same summary contract regardless of tier.

This skill runs **inline (main context)** — it dispatches; the chosen tier provides the context isolation. It must run in main context to reach the Workflow tool when one is available (a subagent cannot dispatch workflows).

## Topic

$ARGUMENTS

If no topic was provided, infer it from the current conversation — identify the technical claim, decision, or implementation being worked on and research that.

## Dispatch decision (multi-topic check, then three tiers)

**Multi-topic check — run FIRST, before any tier.** Count the independent sub-topics in the ask (numbered list, enumerated questions, separable subjects that share no claims). **N ≥ 2 separable topics → do NOT dispatch an engine on the combined blob.** An engine decomposes ONE question into generic research *angles*; fed a multi-topic blob, every broad agent researches all N topics shallowly — N× the wall-clock and tokens for worse depth. Instead: spawn **N parallel topic agents** (Agent tool, `general-purpose`, one per topic, each running the full `/research` discipline; instruct each to cite primary sources by URL — a subagent return without citations is ungrounded synthesis). **Give each agent its own sub-slice** — `<memory_dir>/<slug>/<topic-slug>/`, assigned by this session in the dispatch envelope, never chosen by the worker (two workers choosing independently can choose the same one). Each writes the normal `RESEARCH.md` index, its sidecars, and its own `research-checklist.md` inside that sub-slice; those filenames are fixed, so N agents pointed at one slice root would overwrite one another's index and ledger rather than producing separable artifacts. The main session then synthesizes the slice-root `RESEARCH.md` from the per-topic indexes. An engine is for a SINGLE contested or deep question that needs falsification rounds and adversarial claim-checking.

For a single-topic ask, detection is **engine-biased**: prefer the heaviest available tier UNLESS the task is clearly small/targeted. Unknown scope or any doubt → heavier tier.

| Tier | Condition | Execution |
|---|---|---|
| 1 — workflow engine (preferred) | The Workflow tool is available AND a deep-research workflow exists (a built-in deep-research workflow, or one the consuming project ships) AND the task is heavy/broad (or unknown scope) | Dispatch that workflow with the topic |
| 2 — forked subagent | No workflow path AND the task is heavy | Spawn an isolated `general-purpose` agent running the full `/research` discipline |
| 3 — inline | Task clearly small/targeted (single fact, one obvious source, narrow lookup) | Run `/research` inline in this session |

- **Heavy/broad** = multi-source, multi-vendor, comparison/migration, unfamiliar domain, or research that would flood main context with 9+ external queries.
- **Clearly small** = a single verifiable fact from one obvious source. Even here the full `/research` discipline applies — task size never reduces depth.
- **Multi-topic parallel agents** = each topic agent still runs the FULL `/research` discipline (3 phases, source tiers, falsification) — the split changes orchestration, never depth.

### Tier 1 — workflow engine (preferred)

If your tool list includes the Workflow tool and a deep-research workflow is available (check the consuming project's workflow registry first — a project-provided engine may superset the built-in one), dispatch it with the topic and, if it accepts one, the artifact destination — `<memory_dir>/<slug>/RESEARCH.md`, resolved per the plugin's topic-docs binding ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)). The engine runs in the background; its completion notification carries the summary + artifact path. Surface those to the user. Do **NOT** re-run the research inline.

If no workflow engine resolves, fall through to Tier 2.

### Tier 2 — forked subagent fallback

Spawn a subagent that runs the canonical `/research` workflow in an isolated context:

```text
Agent({
  subagent_type: "general-purpose",
  description: "Deep research (isolated)",
  prompt: "Run the discovery plugin's research skill (/discovery:research) on: <topic> and
           follow its disciplines exactly — the skill loads its own discipline file; do NOT
           reconstruct it here. Carry-verbatim reminders: queries SCALE to open questions,
           not a flat floor; primary source fetched DIRECTLY, not via the SERP; mandatory
           Phase-2 falsification. Discover the research tools connected this session — don't
           assume a fixed set. Every accepted claim needs a primary source cited by URL
           captured this run; uncited claims are ungrounded synthesis. RUN THE OUTCOME GATE
           before returning. Write the RESEARCH.md artifact per the skill's Final step.
           Return ONLY a one-paragraph summary + the artifact path + any unresolved questions."
})
```

`general-purpose` (not a read-only Explore agent) because Phase 3 needs MCP/tool access and the artifact must be written.

### Tier 3 — inline (clearly small task)

Run `/research` inline in this session. No subagent, no workflow. The full `/research` discipline still applies.

## Relationship to `/research` (parent skill)

This variant tracks `/research`'s conventions — same discipline file, same artifact contract, same outcome gate. There is no separate copy here; update the parent and this dispatcher follows.

## Gotchas

- **Feeding a multi-topic ask to an engine.** An engine decomposes ONE question into research
  angles; given N separable topics, every broad agent researches all N shallowly — N× the cost for
  worse depth. Run the multi-topic check FIRST, before any tier selection.
- **Dispatching this skill itself.** It must run in main context: `Workflow` is unavailable in every
  non-fork subagent, and the multi-topic path needs the `Agent` tool, which errors even inside a
  fork. A dispatched `/research-deep` silently loses Tier 1 and the N-topic fan-out — the two things
  it exists for. The sibling `/research` is the one that dispatches.
- **Accepting a subagent return without cited primaries.** That is ungrounded synthesis, Tier 3 by
  the discipline's own rule. Instruct every topic agent to cite primary source URLs, and treat a
  return without them as unfinished rather than as evidence.
- **Assuming the heaviest tier is available.** Tier selection is engine-biased, but it reads what is
  actually connected this session and degrades to the next tier rather than failing.

## What this skill does NOT do

- Does NOT make decisions or write code — research only; the planning step (or user) decides.
- Does NOT skip phases for "simple" topics — task size does not reduce depth.
- Does NOT run the deep pass itself in main context — it dispatches; Tier 1 (engine) or Tier 2 (subagent) provides the context isolation.

## See also

- `/research` — the canonical 3-phase workflow (Tiers 2 + 3 run it; a Tier-1 engine supersets it)
- `${CLAUDE_PLUGIN_ROOT}/skills/research/context/discipline.md` — the shared discipline file
