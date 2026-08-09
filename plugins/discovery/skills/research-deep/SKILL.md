---
name: research-deep
description: "Dispatch deep external research to the heaviest isolated execution tier available — a workflow engine, an isolated subagent, or inline as last resort — keeping the main conversation clean while the full research discipline runs. Itself runs in main context, the only place both the Workflow tool (absent from every non-fork subagent) and a dependable Agent spawn are guaranteed. Use when: 'deep research', 'research these N topics', 'broad multi-source research', 'compare these tools thoroughly', 'migration research', 'exhaustive research on X'; for a single small lookup use the research skill directly, which already dispatches its own subagent."
argument-hint: "[topic] (e.g., /discovery:research-deep <library> <version> best practices, /discovery:research-deep <framework> <feature> migration guide)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: research
  summary: Dispatch deep multi-topic research to the heaviest isolated tier
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

`/research-deep` is the **dispatcher** for deep external research — a depth/execution variant of the sibling `/research` skill. Same research contract (3-phase discipline, source-tier ratio, recency gate, mandatory falsification, cited `RESEARCH.md` artifact); heavier execution that keeps the main session's context clean. It selects ONE execution tier from tool availability + task heaviness, then surfaces the same summary contract regardless of tier.

This skill runs **inline (main context)** — it dispatches; the chosen tier provides the context isolation. It must run in main context because that is the only place both of its requirements hold — the `Workflow` tool, absent from every non-fork subagent, and a dependable `Agent` spawn, which no subagent is guaranteed to hold: see the *Dispatching this skill itself* gotcha.

## Topic

$ARGUMENTS

If no topic was provided, infer it from the current conversation — identify the technical claim, decision, or implementation being worked on and research that.

## Dispatch decision (multi-topic check, then three tiers)

**Multi-topic check — run FIRST, before any tier.** Count the independent sub-topics in the ask (numbered list, enumerated questions, separable subjects that share no claims). **N ≥ 2 separable topics → do NOT dispatch an engine on the combined blob.** An engine decomposes ONE question into generic research *angles*; fed a multi-topic blob, every broad agent researches all N topics shallowly — N× the wall-clock and tokens for worse depth. Instead: spawn **N parallel `discovery:researcher` agents** (Agent tool, one per topic), each dispatched with the full envelope below. **Cap N at roughly a dozen** — past that, narrow the ask with the user before dispatching. **Give each agent its own sub-slice** — `<memory_dir>/<slug>/<topic-slug>/`, assigned by this session in the dispatch envelope, never chosen by the worker (two workers choosing independently can choose the same one); the memory root travels as its own envelope field, since a worker handed a nested sub-slice path cannot tell from that path alone which ancestor is the configured root. Each writes the normal `RESEARCH.md` index, its sidecars, and its own `research-checklist.md` inside that sub-slice; those filenames are fixed, so N agents pointed at one slice root would overwrite one another's index and ledger rather than producing separable artifacts. **This session owns each topic's post-dispatch boundary — synthesis is the last step, not the only one.** Close "The post-dispatch boundary" below for **each** topic, then synthesize the slice-root `RESEARCH.md` from the per-topic indexes. Skipping it produces the worst available artifact: a root `RESEARCH.md` presenting claims as gate-passed when the rows that matter were never graded by anyone. An engine is for a SINGLE contested or deep question that needs falsification rounds and adversarial claim-checking.

For a single-topic ask, detection is **engine-biased**: prefer the heaviest available tier UNLESS the task is clearly small/targeted. Unknown scope or any doubt → heavier tier.

| Tier | Condition | Execution |
|---|---|---|
| 1 — workflow engine (preferred) | The Workflow tool is available AND a deep-research workflow exists (a built-in deep-research workflow, or one the consuming project ships) AND the task is heavy/broad (or unknown scope) | Dispatch that workflow with the topic |
| 2 — isolated subagent | No workflow path AND the task is heavy | Dispatch the purpose-built `discovery:researcher` agent with a resolved envelope |
| 3 — inline | Task clearly small/targeted (single fact, one obvious source, narrow lookup) | Run `/research` inline in this session |

- **Heavy/broad** = multi-source, multi-vendor, comparison/migration, unfamiliar domain, or research that would flood main context with 9+ external queries.
- **Clearly small** = a single verifiable fact from one obvious source. Even here the full `/research` discipline applies — task size never reduces depth.
- **Multi-topic parallel agents** = each topic agent still runs the FULL `/research` discipline (3 phases, source tiers, falsification) — the split changes orchestration, never depth.

### The dispatch envelope — every `discovery:researcher` spawn carries it

Both paths that spawn a worker — the N-topic fan-out and Tier 2 — spawn the same agent with the same envelope, resolved in this session because the agent cannot resolve any of it once started. It refuses to guess, and halts on an absent or ambiguous topic, reason, or slice path.

```text
Agent({
  subagent_type: "discovery:researcher",
  description: "Deep research: <topic>",
  prompt: "Topic: <the resolved research topic>
           Reason: <the decision this research feeds, and who the output is for — on the N-topic path, the slice of that decision THIS topic answers>
           Memory slice: <memory_dir>/<slug>/ — on the N-topic path, the <topic-slug>/ sub-slice assigned to THIS topic
           Memory root: <memory_dir>
           Budget: <the depth this session authorized>
           Capability flags: nested spawning <available|unavailable>"
})
```

**Envelope fields only.** The agent arrives with `/research` preloaded and with its effort and turn budget already calibrated to that discipline, so the mandatory disciplines, the citation rule, the outcome gate — including the split that hands its verifier-owned rows to a fresh-context verifier rather than letting the producer grade them — and the shape of its return payload are all its own standing contract. Restating them in the prompt copies a contract that lives in the parent skill and drifts from it the moment that skill changes. One bound to know when filling `Budget`: the researcher's `maxTurns: 40` is fixed in its definition, so the budget field can narrow depth within that ceiling but never widen past it — a task that genuinely needs more belongs to Tier 1's workflow engine. Field-by-field rationale for five of the six envelope fields: [`${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md`](${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md); `Memory root` is specified by the researcher's own contract ([`${CLAUDE_PLUGIN_ROOT}/agents/researcher.md`](${CLAUDE_PLUGIN_ROOT}/agents/researcher.md)), which names why it must arrive resolved rather than derived.

### Tier 1 — workflow engine (preferred)

If your tool list includes the Workflow tool and a deep-research workflow is available (check the consuming project's workflow registry first — a project-provided engine may superset the built-in one), dispatch it with the topic and, if it accepts one, the artifact destination — `<memory_dir>/<slug>/RESEARCH.md`, resolved per the plugin's topic-docs binding ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)). The engine runs in the background; its completion notification carries the summary + artifact path. Do **NOT** re-run the research inline, and do **not** surface the return as-is — an engine is a producing context like any other, so close the post-dispatch boundary below first.

If no workflow engine resolves, fall through to Tier 2.

### Tier 2 — isolated subagent fallback

Dispatch ONE `discovery:researcher` with the envelope above. With a single worker the slice field is the topic's own `<memory_dir>/<slug>/` — a sub-slice is needed here only when that root already holds an unrelated `RESEARCH.md`, per the parent skill's one-writer-per-slice rule.

`discovery:researcher` rather than a `general-purpose` spawn carrying a hand-written description of the discipline: it is the plugin's purpose-built worker for exactly this run, arriving with `/research` already loaded and with its effort and turn budget calibrated to that discipline, so the run is disciplined and correctly provisioned at turn zero rather than to whatever depth a prompt managed to reproduce. Its tool list also covers what the work needs, which a read-only Explore agent's does not: Phase 3 reaches direct-fetch and MCP tools, and the artifact gets written.

### Tier 3 — inline (clearly small task)

Run `/research` inline in this session — no dispatched *research* tier, no workflow. The full `/research` discipline still applies, including its own rule that an inline run hands the verifier-owned rows to a fresh context rather than self-grading them. That fresh context is a subagent; what Tier 3 declines to dispatch is the research, not the verification, and the boundary below arrives here through the parent skill rather than being restated.

### The post-dispatch boundary — every dispatching tier owns it

**A dispatched run is not finished when it returns.** No producing context — engine, isolated subagent, or topic worker — can complete the `/research` outcome gate's verifier-owned rows (independent corroboration, HIGH confidence) or its parent-owned row (project fit). The first two are assigned to a fresh context precisely because a producer may not grade its own choices; the third needs the consuming project's conventions, which only this session holds. Nor can the producer be relied on to dispatch that verifier itself — whether a non-fork subagent holds `Agent` depends on the harness's current nesting allowance (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`), a default that has moved three times and is not worth designing against.

So for **every** dispatched run — one per topic on the N-topic path, once on Tier 1 and Tier 2 — this session dispatches the sibling verifier against the artifact on disk, applies project fit, and writes both results back into that artifact's index **before** surfacing anything. Surfacing a producer's summary and artifact path directly presents claims as gate-passed when the rows that matter were never graded by anyone. A single-topic ask earns no weaker boundary than a multi-topic one, and an engine earns no weaker boundary than a subagent.

**Grade the run off disk before any of that.** Every obligation above acts on an artifact, so all of them are worthless against a dispatch that produced none — and `status: complete` is the producer's claim about its own run. The parent skill's **post-dispatch acceptance gate** is what turns that claim into evidence: a `mkdir -p <slice> && touch <slice>/.research-dispatch` baseline taken BEFORE the dispatch, then `scripts/check-dispatch-artifact.sh --index-name RESEARCH.md` against the slice path this session resolved (never one read out of the payload), then a parent-side regrade of the coverage ledger. Cite exit statuses; any non-zero halts. **On the N-topic path run it against the sub-slice assigned to each topic, before synthesizing the slice-root index** — the gate reads a root index alongside its sub-slice ones as ambiguous and exits 2, so after synthesis that exit means the wrong path was supplied rather than that a run failed.

Parent-side handling of a `discovery:researcher` return specifically — the gate's steps, the payload checks, and the four obligations stated in full — is the parent skill's contract rather than a second copy here: [`${CLAUDE_PLUGIN_ROOT}/skills/research/SKILL.md`](${CLAUDE_PLUGIN_ROOT}/skills/research/SKILL.md) for the gate's steps, and [`${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md`](${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md) for the rationale and the recovery ladder.

## Relationship to `/research` (parent skill)

This variant tracks `/research`'s conventions — same discipline file, same artifact contract, same outcome gate. There is no separate copy here; update the parent and this dispatcher follows.

## Gotchas

- **Feeding a multi-topic ask to an engine.** An engine decomposes ONE question into research
  angles; given N separable topics, every broad agent researches all N shallowly — N× the cost for
  worse depth. Run the multi-topic check FIRST, before any tier selection.
- **Dispatching this skill itself.** It must run in main context: `Workflow` is unavailable in every
  non-fork subagent, and **every** tier needs the `Agent` tool — the N-topic fan-out to spawn topic
  workers, and all four paths to close the post-dispatch boundary — whose availability inside a
  subagent depends on a nesting default that has moved three times, and which, inside a fork, cannot
  spawn a further fork at all. A dispatched `/research-deep` therefore risks silently losing Tier 1,
  the N-topic fan-out, and the verification boundary that makes any tier's artifact trustworthy. The
  sibling `/research` is the one that dispatches.
- **Treating a worker's return as the finished thing.** A `discovery:researcher` return is a pointer
  plus a payload, and grading that payload is parent-side work this session owes before anything is
  surfaced — the checks and the obligations are specified in the parent skill's dispatch contract.
  Accepting a payload without running them surfaces an ungraded run as a gate-passed one.
- **Assuming the heaviest tier is available.** Tier selection is engine-biased, but it reads what is
  actually connected this session and degrades to the next tier rather than failing.

## What this skill does NOT do

- Does NOT make decisions or write code — research only; the planning step (or user) decides.
- Does NOT skip phases for "simple" topics — task size does not reduce depth.
- Does NOT run the deep pass itself in main context — it dispatches; Tier 1 (engine) or Tier 2 (subagent) provides the context isolation.

## See also

- `/research` — the canonical 3-phase workflow (Tiers 2 + 3 run it; a Tier-1 engine supersets it)
- `${CLAUDE_PLUGIN_ROOT}/skills/research/context/discipline.md` — the shared discipline file
