---
description: "Ranking of optimization targets by evidence quality, from session pain, a named path or telemetry, so an unmeasured system yields 'instrument this first' instead of a guess. Use when: 'what should we optimize', 'find the bottleneck', 'this feels slow', 'is X worth optimizing', 'our git hooks or CI checks are slow'. Skip: a whole-process sweep is /performance:go-faster. Skip when the target is already chosen and measured, or when a failure needs debugging rather than a candidate ranking."
user-invocable: true
argument-hint: "[<path|component|'session'|'telemetry'>]"
disable-model-invocation: false
metadata:
  workflow-stage: explore
  summary: Rank optimization candidates by evidence quality, not suspicion
---

**Arguments.** `[<path|component|'session'|'telemetry'>]`. e.g. /performance:target plugins/disk-hygiene/hooks

## Purpose

Answers **"what should we optimize, and how much do we actually know about it?"**

Never pick a target because its mechanism sounds expensive. A diagnosis blaming WDAC
code-integrity enforcement for slow process spawns is wrong when the data says otherwise, even with
the policy enabled: a spread of min 180.5 ms / median 1107.7 ms / max 2841.3 ms across *identical*
no-op spawns is a contention signature, because a fixed policy check cannot produce a 15x spread.
**The bimodality is the diagnosis; the plausible mechanism is a distraction.**

Rank by evidence, and say so when there is none.

## Inputs it accepts

| Source | What to do |
|---|---|
| The current session's own pain | Name the operation that felt slow and what was observed. A screenshot or recording counts. Anecdote is a valid *candidate source* and an invalid *ranking basis*. |
| A named path or component | Enumerate the layers it spans before choosing one (see "Measure the layers first"). |
| A telemetry store | `/harness-ops:observability` for Claude Code's own; otherwise the project's. Prefer it over every other source, after checking its accuracy and coverage. |
| Slow checks: git hooks, a local check script or CI jobs | Rank per check and lane (see "Slow checks, hooks and CI"). Claude Code's own hooks are the go-faster `hooks` area, not this row. |
| Open-ended "what is slow here" | The open-ended sweep belongs to `/performance:go-faster`; this skill ranks what that sweep, or the user, brings. With nothing brought, expect "instrument this first". |

## Evidence tiers

Rank every candidate into exactly one. **A lower tier never outranks a higher one**, regardless of
how compelling the mechanism sounds.

| Tier | Means | Example |
|---|---|---|
| **E1, attributed measurement** | A measurement that isolates this component's cost from its neighbors' | A spawn census showing this hook costs 4 of the 7 spawns per tool call |
| **E2, aggregate measurement** | A real measurement that includes this component but does not isolate it | "The whole pre-tool path takes 1.2 s" |
| **E3, structural inference** | No measurement; a documented cost model predicts expense | "This is a 125-line shell wrapper that runs per tool call" |
| **E4, suspicion** | A plausible mechanism and nothing else | "WDAC is probably slowing spawns" |

**Nothing above E3 exists means the top recommendation is "instrument this first"**, naming the
cheapest instrument that would reach E2. That is the answer; do not substitute a ranked guess.

Cheap instruments: a [census](../../reference/techniques.md#a-choose-the-target) of what runs on
the hot interaction, and events tagged with the
[region and phase](../../reference/techniques.md#c-lab-measurement-and-rigs) the symptom hits.

## Measure the layers before choosing one

When a candidate spans layers (a shell wrapper around a Python program; a route through an ORM
through a driver), attribute cost *across the layers* before picking one to optimize.

Do not pick the largest layer by size: a 125-line shell wrapper can carry roughly 88% of the cost
while the 1903-line Python guard body it execs is not the bottleneck. Layer attribution is cheap
and reorders the candidate list.

Trace past the headline event too: work no metric covers (background reloads, idle-state work)
still costs. For a field report with a recording, follow the diagnosis ladder before theorizing.
See [diagnose](../../reference/techniques.md#e-diagnose).

To name a candidate's mechanism, find the row of the profile-to-family table in
[optimization patterns](../../reference/techniques.md#f-optimization-patterns-latency-catalog) that
the evidence matches; a mechanism with no matching row is not named. A deletion candidate is the
exception: it comes from reading the path's callers, so it ranks E3 until a measurement covers it.

## Slow checks, hooks and CI

A repository's checks run in lanes: a commit hook, a push hook and CI. Treat each lane as a layer
and attribute before choosing.

1. **Inventory each check and its lane** from the repository's hook-manager config, its check
   scripts and its CI workflows. Read the repository's own placement record and budgets first (rules,
   conventions, agent instructions); they override this skill. This repository's worked case is the
   [check-placement contract, Duration budgets](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/check-placement/README.md#duration-budgets);
   borrow no number from it. With no recorded budget, setting one is `/performance:goal`'s job.
2. **One candidate per check and lane**, the lane named in the Candidate cell
   (`shell lint, pre-commit`). A lane total is E2; one check timed alone in its lane is E1.
3. **The baseline is p50 and p90 per lane**, on a named sample of changed files (one file, a
   typical change, a large change), never a single run. `/performance:goal` records that list.
4. **Rank these moves per candidate**, each at the tier its evidence earns:
   - **Scope to the change**: the check reads only the staged or pushed files it applies to.
   - **Move to a later lane**: a slow check goes from commit to push, or from push to CI. Never drop
     it: CI stays the hard stop, whatever a local hook runs.
   - **Run in parallel**: the runner must report every job's failure and exit non-zero on any; a
     runner that returns only its last job's status passes a failed check. Confirm the shell's or
     hook manager's exit semantics at run time.
   - **Turn on the tool's cache or incremental mode**, keyed so a cold CI runner still checks
     everything.
   - **Swap the tool** for a faster one that covers the same rules.
5. **An upgrade or swap carries a dependency-collision check**: every other tool that loads the one
   being replaced or upgraded still resolves to a version that supports it, read from the package
   manager's dependency tree before the change is proposed.
6. **Resolve stack specifics at run time**: which faster tool exists, its cache and incremental
   flags and the runner's parallel semantics come from `/discovery:research` and the repository's
   own conventions, never from this skill.

**A check that got faster because it checked nothing is broken, not fast.** Before and after a
change, confirm each check reports the files it inspected; a zero-input pass is a finding.

**Checks slow as the repository grows.** Fill the Growing state column with the counter that grows
(files a check scans, test suites a change selects, checks per lane) and route it to
`/toolchain:ratchet`, which holds a counter, never a duration.

## Name the counter, not just the duration

For each ranked candidate, name the **drift-immune counter** that would settle it: process spawns,
syscalls, queries, allocations, bytes, round trips. A counter is reproducible on a host whose wall
clock is not.

The [counter catalog](../../reference/techniques.md#c-lab-measurement-and-rigs) lists
deterministic counters to try before timing. If no counter exists for a candidate, say so
explicitly: it changes what `/performance:goal` can promise.

Counts over wall clock is sourced only for **instruction counts** (Valgrind's Cachegrind manual;
Iai); extending it to spawns, syscalls and queries is this plugin's own generalization, and
Valgrind's manual also argues execution time "is a better metric than instruction counts because
it's what users perceive". Present a counter as *reproducible*, never as *more truthful*.

## Output

A ranked table, highest evidence tier first:

| Rank | Candidate | Tier | What is known | Counter that would settle it | Cheapest next instrument |
|---|---|---|---|---|---|

Add a **Growing state** column when the candidate reads state whose size grows with use (transcripts,
logs, histories, accumulating caches): `yes — /performance:goal will require scaling arms` or `no`.
When `yes`, name what grows and the smallest realistic span of sizes to measure (not a single point).

Then one line naming the recommended target and the tier it rests on. If that tier is E3 or E4, the
recommendation is to instrument, not to optimize.

On a re-scan after a MET result, look first for the next slow spot in the same journey or path.

## Boundary

- **Does not set a goal or a target number.** That is `/performance:goal`, which is human-gated
  because it needs the floor computed and the realistic/ideal split agreed.
- **Does not measure.** It ranks what is known and names what is missing;
  `/performance:snapshot` captures.
- **Does not root-cause an observed failure.** A specific broken or slow behavior with a
  reproduction is a debugging task, not a candidate ranking.
- **Does not read a captured profile down to a line.** A CPU profile, trace or heap snapshot
  already on disk goes to `/debugging:analyze-profile` when the debugging plugin is enabled;
  otherwise open it in the tool that recorded it. Either way, its finding enters this ranking as
  E1 or E2 evidence.
- **Does not diagnose a slow Claude Code installation.** That is
  `/harness-ops:audit-performance`, which this skill consumes as a telemetry source rather than
  duplicating.

## Next

- A chosen target: `/performance:goal <chosen target>`. Carry the evidence tier forward: goal stops
  on an E3 or E4 candidate, or one this ranking says to instrument, until the named instrument has
  run.
- No candidates yet and a whole-process sweep wanted: /performance:go-faster.
- A check count growing with the repository: /toolchain:ratchet <the counter>.

## Gotchas

- **A plausible mechanism is not evidence.** The WDAC diagnosis above is the worked example. Ask what
  the mechanism predicts, then check whether the data shows it. A fixed cost cannot produce a
  variable spread.
- **Anecdote from this session is a candidate source, not a ranking basis.** "It felt slow" gets a
  candidate onto the list at E4 and no higher.
- **The biggest file is not the bottleneck.** Line count is not a cost model. Attribute across the
  layers before believing size.
- **A target with no drift-immune counter is a harder target**, not an equal one. Say so here rather
  than discovering it in `/performance:snapshot` when a wall-clock claim gets refused.
- **Growing-state reads need a scaling arm in the goal.** Flag them in the table so
  `/performance:goal` does not settle on one transcript size while production grows without bound.
