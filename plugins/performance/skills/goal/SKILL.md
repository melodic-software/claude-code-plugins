---
description: "Construct a performance goal the data can actually settle: the metric and the exact command that produces it, a REALISTIC target and an IDEAL target held separately, and the irreducible FLOOR computed BEFORE any work. Surfaces 'your target is below the measured floor, no code change can reach it' up front and makes the human decide, instead of silently failing the goal at the end. Human-gated always: this is the one phase that may never run unattended. Use when: 'set a performance target', 'how fast should this be', 'what is a realistic goal', 'is this target achievable', 'define done for this optimization', 'what is the floor here'. Runs after /performance:target and before /performance:snapshot. Skip when the work is exploratory with no claim to defend, or when the target is a correctness fix that happens to also be faster."
user-invocable: true
argument-hint: "[<target>] (e.g. /performance:goal the destructive-guard PreToolUse hook)"
disable-model-invocation: false
metadata:
  workflow-stage: plan
  summary: Build a goal with realistic and ideal targets plus a computed floor
---

## Purpose

Answers **"what would count as done, and is it reachable at all?"**

The failure this prevents: the source run behind this plugin set a goal of p50 <= 250 ms for a hook
on a host that charged 0.3-2.8 s for a single irreducible process spawn. The goal was **unreachable
by any code change**, and that was discovered at the end, after the work. Knowing it up front would
have reframed the entire task from "make it fast" to "remove the spawn or accept the floor".

## Human-gated, always

This phase requires the user. `/performance:snapshot` and `/performance:verify` may run unattended;
this one may not, under any autonomy setting.

The reason is specific: computing the floor routinely produces a verdict the user has to act on
("this target is unreachable"), and choosing between a reframed goal, a different target, and
accepting the floor is a judgment about what the work is for. An agent resolving that on the user's
behalf converts a surfaced constraint back into a silent one.

If the user is unavailable, **stop and say what is blocked**. Do not pick a target and proceed.

## What a goal must contain

### 1. The metric, and the exact command that produces it

Not "latency". The literal command, its arguments, and the field of its output that is the number.
A metric nobody can re-run is not a metric.

Name the **drift-immune counter** alongside it (spawns, syscalls, queries, allocations, round trips)
and rank the counter above the duration. On a host that cannot support a wall-clock claim, the
counter is what survives; in the source run the durable result was a spawn census of 4 -> 1, and the
milliseconds were not reproducible by an independent verifier on the same machine an hour later.

### 2. The floor, computed before any work

The irreducible cost this target cannot go below whatever the code does. Compute it by measuring the
cheapest possible version of the operation: the empty hook, the no-op spawn, the single round trip,
the query returning one row.

`lib/spawn_noise.py`'s `spawn_probe()` gives the process-spawn floor for this host directly.

Then compare:

- **target > floor**: proceed.
- **target close to floor**: the goal is reachable only by removing the irreducible operation, not
  by making it faster. Say that explicitly; it is a different piece of work.
- **target < floor**: **STOP and surface it.** No code change reaches this target. The user
  decides: reframe the goal, change the target, remove the operation, or accept the floor.

### 3. Two targets, held separately

- **Realistic**: what this change is expected to achieve, given the floor and the measured baseline.
- **Ideal**: what the operation would cost with no incidental overhead at all.

Both are recorded. A single target collapses "did we succeed" and "how much is left" into one number
and loses the second.

### 4. What counts as done

Including whether merge is in scope, and whether a behavior change disqualifies the result. A
correctness regression outranks any speedup and is reported separately, never folded into the
performance claim.

## Percentiles and sample count

Default: **p50 and p95 over at least 20 samples**, alongside the counter.

State plainly that this is a **house convention, not field consensus**:

- The pattern "a median plus a high-order percentile" is grounded. Google's SRE Book (ch. 4) frames
  the high-order percentile as the "plausible worst case" and the median as the "typical case". But
  the percentiles that chapter names are the **99th and 99.9th**; p95 is convention.
- **No benchmarking-community sample count exists** for what makes a percentile meaningful. The only
  real constraint is arithmetic: a percentile `p` needs at least `1/(1-p)` samples to be expressible
  at all. p95 needs 20; p99 needs 100. `percentile_floor()` in `lib/spawn_noise.py` computes it, and
  that floor **is** enforced.
- Do not cite coordinated omission (Gil Tene) to justify percentiles here unless the harness is a
  load generator. It is a load-generator problem; citing it for a synchronous harness that measures
  every operation miscites the field's best-known source.

If the user wants p99, say what it costs: 100 samples on a host where one spawn can take 2.8 s.

## Output

Write the goal into the topic's `PLAN.md`, and keep baselines in the memory tier
(`.work/<topic-slug>/baselines/`, machine-bound, never committed) per `/verification:measure`.

```text
Metric:     <exact command> -> <field>
Counter:    <drift-immune counter>   [ranked above the duration]
Floor:      <value> (measured by: <command>)
Realistic:  <value>    Ideal: <value>
Percentiles: p50, p95 over N>=20   [house convention; floor 1/(1-p) enforced]
Done when:  <criteria, including whether merge is in scope>
Evidence tier of the target: <E1..E4 from /performance:target>
```

## Boundary

- **Does not measure the baseline.** That is `/performance:snapshot`. This phase measures only the
  floor, because the floor is an input to the goal rather than a result of it.
- **Does not implement.** The change is `/implementation:implement`.
- **Does not store baselines.** `/verification:measure` owns baseline capture and storage; this
  plugin depends on it rather than reimplementing it.

## Next

`/performance:snapshot baseline`.

## Gotchas

- **Compute the floor before agreeing the target, not after.** This is the entire point. A goal
  agreed first and floored second is the failure that produced this skill.
- **The floor is a property of the host, not of the code.** Re-measure it on a different machine;
  never carry a floor across hosts.
- **"Faster" is not a metric.** If the user cannot name the command, the goal is not yet a goal.
- **An ideal target is not a stretch goal.** It is the no-incidental-overhead cost, used to say how
  much room is left after a realistic win.
- **A goal built on an E3/E4 candidate must record that.** Optimizing an unmeasured target can
  succeed against its own metric and change nothing a user perceives.
