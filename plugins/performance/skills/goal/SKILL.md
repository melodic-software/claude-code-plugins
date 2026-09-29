---
description: "Construct a performance goal the data can settle: metric, command, realistic vs ideal targets, and the floor before any work. Surfaces 'your target is below the measured floor, no code change can reach it' up front. Human-gated; never unattended. Use when: 'set a performance target', 'is this target achievable', 'define done for this optimization', 'what is the floor here'. After /performance:target, before /performance:snapshot."
user-invocable: true
argument-hint: "[<target>]"
disable-model-invocation: false
metadata:
  workflow-stage: plan
  summary: Build a goal with realistic and ideal targets plus a computed floor
---

**Arguments.** `[<target>]`. e.g. /performance:goal the destructive-guard PreToolUse hook

## Purpose

Answers **"what would count as done, and is it reachable at all?"**

The failure this prevents: a goal of p50 <= 250 ms on a host that charges 0.3-2.8 s for one
irreducible process spawn is **unreachable by any code change**, and a goal agreed before the floor
is computed hides that until the work is spent. Computing the floor first reframes the task from
"make it fast" to "remove the spawn or accept the floor".

## Human-gated, always

This phase requires the user. `/performance:snapshot` and `/performance:verify` may run unattended;
this one may not, under any autonomy setting.

The floor routinely produces a verdict the user has to act on ("this target is unreachable"), and
choosing between a reframed goal, a different target, and accepting the floor is a judgment about
what the work is for. An agent resolving it converts a surfaced constraint back into a silent one.
If the user is unavailable, **stop and say what is blocked**; do not pick a target and proceed.

## What a goal must contain

### 0. Inputs: the ranked candidate

Read the ranking `/performance:target` produced and quote the chosen candidate's row verbatim
(rank, tier, what is known, the settling counter, the cheapest next instrument). That row is the
object this goal is about, and its tier is the one the Output's `Target` line carries.

- **The ranking says to instrument this candidate first** (tier E3 or E4, or its closing line
  recommends instrumenting, not optimizing): **STOP.** A goal cannot be set on a cost nobody has
  measured. Run the named instrument, then `/performance:target` again.
- **No ranking exists** (the user came straight here with a chosen, measured target): record the
  evidence the user names and the tier it earns under `/performance:target`'s tier table. Never
  leave the tier blank or use the baseline's tier, which answers a different question.

### 1. The metric, and the exact command that produces it

Not "latency". The literal command, its arguments, and the field of its output that is the number.
A metric nobody can re-run is not a metric.

Name the **drift-immune counter** alongside it (spawns, syscalls, queries, allocations, round trips)
and rank the counter above the duration. On a host that cannot support a wall-clock claim, the
counter survives: a spawn census of 4 -> 1 still reproduces when the milliseconds behind it do not,
because a verifier an hour later meets different load.

**Correlation, required.** Record the evidence that moving the counter moved the duration; a counter
that does not track the duration is a hill nobody should climb. `unproven` is a legal value and
travels to the verify report beside the headline counter. The two-rig recipe is in
`/performance:snapshot`; see [prove the proxy](../../reference/techniques.md#d-prove-the-proxy).

**Measurement boundary.** Name the start event, the end event, and which side of any process or
network split each falls on. Name the start state too (cold start, fresh load, warm path): each is a
different measurement. End at the moment the user or caller can act, not when loading finishes.
See [goal and boundary](../../reference/techniques.md#b-define-the-goal-and-its-boundary).

**Parallel units on one event.** When units run in parallel behind one user-visible event, the user
waits for the slowest, not the sum. Record the event's wall-clock time (`Event:`) and the unit's
marginal cost over the next-slowest peer (`Unit:`); an event-level target sits beside the unit-level
ones, and summed CPU or syscall totals never replace it. Procedure and the hooks example:
[parallel units](../../reference/techniques.md#parallel-units-on-one-event).

**Scaling arm when state grows with use.** When the subject reads state that grows with real use
(transcripts, logs, queues, caches, databases), measure at two or more sizes spanning realistic use
and record each size and result (`Scaling:`). **Done when** states a bound on growth; when the human
has not stated one, the goal is not locked: stop and say what is blocked, and do not pick the bound.
`/performance:verify` fails a bound not demonstrated at every recorded size. Procedure:
[scaling arm](../../reference/techniques.md#scaling-arm-when-state-grows-with-use).

**Code path under test, required.** Name the code path(s) the metric exercises and the **observable**
that identifies each: a marker file, an exit code, the set of processes spawned. A goal that names no
path is not locked. A harness can sit on a rare branch without erroring: in #4437 a stale
`bench.launched` marker sent every Stop-hook sample down the rare Python path while the common skip
path went unmeasured. `/performance:snapshot` step 2b resets or records the path-selecting state
before each arm and reports which path ran.

### 2. The floor, computed before any work

The irreducible cost this target cannot go below whatever the code does. Compute it by measuring the
cheapest possible version of the operation: the empty hook, the no-op spawn, the single round trip,
the query returning one row.

`lib/spawn_noise.py`'s `spawn_probe()` gives the process-spawn floor for this host. Pass its summary
to `is_measurable(summary)` and quote the returned reason verbatim before stating any wall-clock
floor. Contention is a two-part predicate: a spread at or above 3.0x across identical no-op spawns
AND a slow mode at or above 500 ms. A wide spread alone is a healthy cold-then-warm host, so never
assert "this host drifts with load" from `spread_ratio` alone. A False keeps the floor in counter
terms (spawns per operation), not milliseconds.

Then compare:

- **target > floor**: proceed.
- **target close to floor**: the goal is reachable only by removing the irreducible operation, not
  by making it faster. Say that explicitly; it is a different piece of work.
- **target < floor**: **STOP and surface it.** No code change reaches this target. The user
  decides: reframe the goal, change the target, remove the operation, or accept the floor.

### 3. Two targets, held separately

- **Realistic**: what this change is expected to achieve, given the floor and the measured baseline.
- **Ideal**: what the operation would cost with no incidental overhead at all.

Record both: a single target collapses "did we succeed" and "how much is left" into one number.

### 4. What counts as done

Including whether merge is in scope and whether a behavior change disqualifies the result. A
correctness regression outranks any speedup and is reported separately from the performance claim.

## Percentiles and sample count

Default: **p50 and p95 over at least 20 samples**, alongside the counter.

State plainly that this is a **house convention, not field consensus**:

- "A median plus a high-order percentile" is grounded: Google's SRE Book (ch. 4) frames the
  high-order percentile as the "plausible worst case" and the median as the "typical case". But the
  percentiles it names are the **99th and 99.9th**; p95 is convention.
- **No benchmarking-community sample count exists** for a meaningful percentile. The only real
  constraint is arithmetic: percentile `p` needs at least `1/(1-p)` samples to be expressible (p95
  needs 20, p99 needs 100). `percentile_floor()` in `lib/spawn_noise.py` computes it, and that floor
  **is** enforced.
- Do not cite coordinated omission (Gil Tene) for percentiles here unless the harness is a load
  generator; a synchronous harness that measures every operation miscites it.

If the user wants p99, say what it costs: 100 samples on a host where one spawn can take 2.8 s.

## Output

Write the goal into the topic's `PLAN.md`, and keep baselines in the memory tier
(`.work/<topic-slug>/baselines/`, machine-bound, never committed). That is `/verification:measure`'s
layout, followed here whether or not the `verification` plugin is installed, so the two never keep
two different baseline stores.

```text
Metric:     <exact command> -> <field>
Counter:    <drift-immune counter>   [ranked above the duration]
Correlation: <evidence the counter moves the duration> | unproven   [REQUIRED]
Path:       <code path(s) under test> (observable: <marker | exit code | process set>)   [REQUIRED]
Boundary:   start <event> -> end <event>; <which side of the split each falls on>; <start state>
Event:      <wall-clock metric when units run in parallel> | n/a
Unit:       <unit under study + marginal over next-slowest peer> | n/a
Floor:      <value> (measured by: <command>)
Realistic:  <value>    Ideal: <value>   [event-level realistic/ideal when parallel]
Percentiles: p50, p95 over N>=20   [house convention; floor 1/(1-p) enforced]
Scaling:    <growing input, sizes, per-arm results, bound> | n/a: subject reads no growing state
Done when:  <criteria, including whether merge is in scope and any scaling bound on growing state>
Target (from /performance:target): <candidate> @ <E1..E4>
```

## Boundary

- **Does not measure the baseline.** That is `/performance:snapshot`; this phase measures only the
  floor, an input to the goal rather than a result of it.
- **Does not implement.** The change is `/implementation:implement`.
- **Does not store baselines.** `/verification:measure` owns baseline capture and storage when the
  `verification` plugin is installed; this plugin depends on it rather than reimplementing it.

## Next

`/performance:snapshot baseline`.

## Gotchas

- **The floor is a property of the host, not of the code.** Re-measure it on a different machine;
  never carry a floor across hosts.
- **An ideal target is not a stretch goal.** It is the no-incidental-overhead cost, showing how much
  room is left after a realistic win.
- **A metric that stays green while the reported symptom is visible is the wrong metric.** A
  composite score inside its "good" band can hide a visible defect; measure the raw events under it.
- **One size is not enough when the subject re-reads growing state.** The claude-ops
  `hook-failure-audit.sh` Stop hook took 137 ms on a 50 KB transcript, 1,374 ms on 2 MB, and
  6,977 ms on 10 MB, with a constant 3 processes per fire, so a spawn counter alone would have
  passed it. A constant counter does not rule out size-proportional cost: measure the duration at
  two sizes even when the counter is flat. Claim: those timings and the constant process count of
  3. Basis: issue #4389 (22 runs per size). As-of: 2026-09-29. Recheck when #4389 is edited or the
  hook is rewritten.
