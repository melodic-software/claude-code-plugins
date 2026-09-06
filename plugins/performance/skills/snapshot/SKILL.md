---
description: "Capture a baseline or post-change performance snapshot with the HOST QUALIFIED FIRST: repeated no-op spawns characterize the machine's own noise, and a wall-clock claim is REFUSED outright from a host carrying the bimodal contention signature, naming the drift-immune counter it can still report instead. Interleaves before/after arms within one run rather than comparing two passes, since a host that drifts 6x in an hour attributes its own drift to the change. Reports a counter alongside and ranked above any duration. Use when: capturing a before or after snapshot, running the comparison between them, or asking whether this machine can support a timing claim at all: 'capture a baseline', 'take a post snapshot', 'run the A/B', 'can I even measure here'. Runs after /performance:goal; hands off to /performance:verify. Skip when no goal with a computed floor exists yet (run /performance:goal), or when the claim is about code shape rather than runtime (that is /verification:measure metrics)."
user-invocable: true
argument-hint: "[baseline|post] [<target>] (e.g. /performance:snapshot baseline, /performance:snapshot post)"
disable-model-invocation: false
metadata:
  workflow-stage: verify
  summary: Capture a snapshot only from a host proven measurable
---

## Purpose

Answers **"what does this cost, and is this machine even able to tell me?"**

Read [`${CLAUDE_PLUGIN_ROOT}/reference/harness-integrity.md`](${CLAUDE_PLUGIN_ROOT}/reference/harness-integrity.md) before writing any harness
here. It is not optional background: a harness that returns a confident wrong answer looks exactly
like one that works, and a check written specifically to avoid being fooled is not exempt.

## Phase order, and why it is this order

### 1. Qualify the host, before measuring anything

The lib is plugin-bundled, not installed, so it needs its directory on `sys.path` before the
import. Anchor to the plugin root rather than the working directory; a bare
`from spawn_noise import ...` raises `ModuleNotFoundError` unless the caller happens to already be
in `lib/`.

```python
import sys
from pathlib import Path

lib = Path(__file__).resolve().parents[3] / "lib"   # <plugin-root>/lib
if str(lib) not in sys.path:
    sys.path.insert(0, str(lib))

from spawn_noise import spawn_probe, is_measurable  # noqa: E402

summary = spawn_probe()
measurable, why = is_measurable(summary)
```

`parents[3]` is correct from `<plugin-root>/skills/<skill>/scripts/x.py`. Count the levels for
wherever the caller actually sits rather than copying the index.

`is_measurable()` returns a verdict and its basis. A `False` is a **hard refusal to report a
wall-clock number**, subject only to the recorded override below.

The refusal names what it can still report. That matters: an unexplained refusal gets overridden
reflexively. On a host that fails `is_measurable()`, the durable result is a deterministic spawn
count of 4 -> 1, not a duration.

**Say plainly that this refusal is a house rule.** No surveyed benchmarking tool refuses above a
variance threshold: pyperf, Criterion, JMH and benchstat all warn and print the number anyway.
pyperf's own thresholds (stdev >= 10% of the mean, min/max >= 50% from the mean, shortest value
< 1 ms) are warnings. Presenting this refusal as consensus would be a miscitation.

### 2. Capture the drift-immune counter first

Spawns, syscalls, queries, allocations, round trips. The counter is the headline; the duration is
context. A counter also catches harness bugs immediately, because a counter that does not move when
it should is an unambiguous signal, while a duration that does not move is ambiguous.

Re-measure the counter after **every** change. A self-inflicted harness bug surfaces first as a
counter that fails to move when it should.

### 3. Capture durations, only if step 1 allowed it

p50 and p95 over at least 20 samples, per the goal. Enforce the arithmetic floor: a percentile `p`
needs `1/(1-p)` samples to be expressible at all (`percentile_floor()` in `lib/spawn_noise.py`).
Report **no** percentile the sample count cannot support; report the raw samples instead.

Never a single sample. Never a bare mean.

## Comparing before and after

**Never compare two separate passes on a drifting host.** A bare `bash -c true` can cost 1825 ms and
283 ms in the same hour on the same machine at ~10% CPU. Any two-pass comparison attributes that 6x
to the change.

Two valid modes:

### Sequential interleaving (default)

Alternate arms within one run, flipping the order each iteration. Report the median of per-pair
ratios alongside per-arm percentiles.

Grounded, Tier 1, `benchstat`'s own documentation: *"The best way to do this is to interleave before
and after runs, rather than running, say, 10 iterations of the before benchmark, and then 10
iterations of the after benchmark."*

**Under uncontrolled concurrent load, suppress the paired ratio** and report per-arm percentiles
only. The arms are no longer load-matched, and pairing by index compares samples that never shared
conditions.

Do not describe this as "paired statistics, per benchstat". `benchstat` recommends interleaved
*collection* and then analyzes with the **Mann-Whitney U test**, which is an independent two-sample
test. Its `-delta-test` flag no longer exists.

### Simultaneous duet (for a genuinely shared machine)

Run both arms **at the same time** and report only their relative performance.

Grounded, Tier 2: Bulej, Horký, Tůma, Farquet & Prokopec, ["Duet Benchmarking: Improving Measurement
Accuracy in the Cloud"](https://arxiv.org/abs/2001.05811) (ICPE 2020) measured accuracy improvements
of **5.03x** (ScalaBench/DaCapo) and **37.4x** (SPEC CPU 2017) on shared machines from running arms
in parallel, because both arms absorb the same interference.

This is the reverse of the sequential rule and it is not a contradiction: sequential interleaving is
vulnerable to bursty load precisely because the arms run at different moments. **The reconciliation
"only the sequential form is vulnerable" is this plugin's reading, not a sourced claim.** Duet costs
2x the resources and needs the arms to be genuinely independent.

## Warmup

Discard N warmup iterations if the target has a warm path. Do **not** claim this establishes steady
state: Barrett et al. (OOPSLA 2017) found *"at most 43.5% of ⟨VM, benchmark⟩ pairs consistently
reach a steady state of peak performance."* No source justifies any particular N.

## The override

Gates here hard-block. A named per-gate override exists, and using it **records itself in the
report**:

```text
OVERRIDE: unmeasurable-host  reason: <stated by the human>  gate: is_measurable
```

An override without a recorded reason is not available. A report carrying an override says so at the
top, not in a footnote.

## Storage

Baselines live in the memory tier, `.work/<topic-slug>/baselines/`, machine-bound, **never
committed**.

That layout matches `/verification:measure`, which owns baseline capture and storage mechanics.
Invoke it via the Skill tool **when the `verification` plugin is installed**, so the two never keep
two different baseline stores. When it is absent, capture into the same path directly and say in the
report that the capture was unassisted. The dependency is a preference for reuse, not a hard
requirement: this skill's own gates (host qualification, interleaving, the counter, the refusal)
work either way, and refusing to measure because a sibling plugin is missing would be a worse
failure than the duplication it avoids.

A committed baseline is a number that outlives the conditions that made it true. No source states
"a stored baseline is invalid on another machine" outright, but four independent Tier 1/2 strands
converge on it; the practical rule is to always re-measure both arms rather than compare against a
stored one.

## Boundary

- **Does not own baseline/compare mechanics.** `/verification:measure` does. This adds host
  qualification, interleaving, counters, and the refusal.
- **Does not implement the change.** `/implementation:implement` does.
- **Does not decide whether the goal was met.** That is `/performance:verify`.

## Next

`/performance:verify`.

## Gotchas

- **The refusal must always name the counter it can still report.** A dead-end refusal gets
  overridden reflexively and teaches nothing.
- **`is_measurable()` reads the findings list, never `spread_ratio` alone.** The bimodal predicate is
  two-part: a wide spread whose slow mode is *also* slow. A bare ratio check fires on a healthy
  cold-then-warm host.
- **`$(...)` is a process spawn on MSYS.** A "builtins-only" hot path that reports through stdout
  still costs a full process, and a spawn census that ignores its own substitutions undercounts.
- **A `PATH` shim directory from `mktemp -d` invalidates a `PATH`-keyed cache every run.** The
  harness then measures its own randomization and reports "no improvement".
- **Report the counter even when the duration is allowed.** The counter is what an independent
  verifier can reproduce tomorrow.
