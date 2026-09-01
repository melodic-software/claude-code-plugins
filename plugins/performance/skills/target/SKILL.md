---
description: "Identify and rank optimization targets by EVIDENCE QUALITY rather than by suspicion, so an unmeasured system yields 'instrument this first' instead of a guess. Accepts targets from the current session's own pain, a named path or component, a telemetry store, or an open-ended 'what is slow here'. Ranks each candidate by how well its cost is actually attributed, names the drift-immune counter that would settle it, and refuses to rank an unmeasured candidate above a measured one however plausible its mechanism. Use when: 'what should we optimize', 'what is slow here', 'find the bottleneck', 'where is the time going', 'this feels slow', 'pick a performance target', 'is X worth optimizing'. Entry point for the measurement-first optimization workflow; hands off to /performance:goal. Skip when the target is already chosen and measured (go straight to /performance:goal), or when a specific failure needs root-causing rather than a candidate ranking (that is debugging)."
user-invocable: true
argument-hint: "[<path|component|'session'|'telemetry'>] (e.g. /performance:target plugins/disk-hygiene/hooks)"
disable-model-invocation: false
metadata:
  workflow-stage: discovery
  summary: Rank optimization candidates by evidence quality, not suspicion
---

## Purpose

Answers **"what should we optimize, and how much do we actually know about it?"**

The failure this prevents is picking a target because its mechanism sounds expensive. In the source
run behind this plugin, a parallel session diagnosed WDAC code-integrity enforcement as the cause of
slow process spawns. The mechanism was real and the policy was genuinely enabled. It was still the
wrong answer, and had to be retracted: a spread of min 180.5 ms / median 1107.7 ms / max 2841.3 ms
across *identical* no-op spawns is a contention signature, because a fixed policy check cannot
produce a 15x spread. **The bimodality was the diagnosis; the plausible mechanism was a
distraction.**

So this skill ranks by evidence, and says so when there is none.

## Inputs it accepts

| Source | What to do |
|---|---|
| The current session's own pain | Name the operation that felt slow and what was observed. Anecdote is a valid *candidate source* and an invalid *ranking basis*. |
| A named path or component | Enumerate the layers it spans before choosing one (see "Measure the layers first"). |
| A telemetry store | `/claude-ops:observability` for Claude Code's own; otherwise the project's. Prefer it over every other source. |
| Open-ended "what is slow here" | Widest scope, weakest evidence. Expect the output to be "instrument this first". |

## Evidence tiers

Rank every candidate into exactly one. **A lower tier never outranks a higher one**, regardless of
how compelling the mechanism sounds.

| Tier | Means | Example |
|---|---|---|
| **E1, attributed measurement** | A measurement that isolates this component's cost from its neighbours' | A spawn census showing this hook costs 4 of the 7 spawns per tool call |
| **E2, aggregate measurement** | A real measurement that includes this component but does not isolate it | "The whole pre-tool path takes 1.2 s" |
| **E3, structural inference** | No measurement; a documented cost model predicts expense | "This is a 125-line shell wrapper that runs per tool call" |
| **E4, suspicion** | A plausible mechanism and nothing else | "WDAC is probably slowing spawns" |

**Nothing above E3 exists means the top recommendation is "instrument this first"**, naming the
cheapest instrument that would reach E2. That IS the answer; do not substitute a ranked guess.

## Measure the layers before choosing one

When a candidate spans layers (a shell wrapper around a Python program; a route through an ORM
through a driver), attribute cost *across the layers* before picking one to optimize.

The source run's first instinct was to optimize a 1903-line Python guard body. Measurement showed
the 125-line shell wrapper around it was roughly 88% of the cost and the Python was not the
bottleneck. Layer attribution is cheap and reorders the candidate list.

## Name the counter, not just the duration

For each ranked candidate, name the **drift-immune counter** that would settle it: process spawns,
syscalls, queries, allocations, bytes, round trips. A counter is reproducible on a host whose wall
clock is not.

If no counter exists for a candidate, say so explicitly. That is a real property of the target and
it changes what `/performance:goal` can promise.

Grounding: the counts-over-wall-clock rationale is stated in the literature for **instruction
counts** specifically (Valgrind's Cachegrind manual; Iai). Extending it to spawns, syscalls and
queries is this plugin's own generalization, not a sourced claim, and Valgrind's own manual argues
the other side too: execution time "is a better metric than instruction counts because it's what
users perceive". Present a counter as *reproducible*, never as *more truthful*.

## Output

A ranked table, highest evidence tier first:

| Rank | Candidate | Tier | What is known | Counter that would settle it | Cheapest next instrument |
|---|---|---|---|---|---|

Then one line naming the recommended target and the tier it rests on. If that tier is E3 or E4, the
recommendation is to instrument, not to optimize.

## Boundary

- **Does not set a goal or a target number.** That is `/performance:goal`, which is human-gated
  because it needs the floor computed and the realistic/ideal split agreed.
- **Does not measure.** It ranks what is known and names what is missing;
  `/performance:snapshot` captures.
- **Does not root-cause an observed failure.** A specific broken or slow behavior with a
  reproduction is a debugging task, not a candidate ranking.
- **Does not diagnose a slow Claude Code installation.** That is
  `/claude-ops:audit-performance`, which this skill consumes as a telemetry source rather than
  duplicating.

## Next

`/performance:goal <chosen target>`. Carry the evidence tier forward: a goal built on an E3
candidate must say so.

## Gotchas

- **A plausible mechanism is not evidence.** The retracted WDAC diagnosis above is the worked
  example. Ask what the mechanism predicts, then check whether the data shows it. A fixed cost cannot
  produce a variable spread.
- **Anecdote from this session is a candidate source, not a ranking basis.** "It felt slow" gets a
  candidate onto the list at E4 and no higher.
- **The biggest file is not the bottleneck.** Line count is not a cost model. Attribute across the
  layers before believing size.
- **A target with no drift-immune counter is a harder target**, not an equal one. Say so here rather
  than discovering it in `/performance:snapshot` when a wall-clock claim gets refused.
