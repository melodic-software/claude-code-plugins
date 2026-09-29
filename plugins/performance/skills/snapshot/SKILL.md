---
description: "Capture a baseline or post-change snapshot with the host qualified first: refuse a wall-clock claim from a bimodal-contention host and name the drift-immune counter instead. Interleaves before/after arms in one run. Use when: 'capture a baseline', 'take a post snapshot', 'run the A/B', 'can I even measure here'. Runs after /performance:goal; hands off to /performance:verify. Skip when no goal with a computed floor exists, or when the claim is code shape (/verification:measure)."
user-invocable: true
argument-hint: "[baseline|post] [<target>]"
disable-model-invocation: false
metadata:
  workflow-stage: verify
  summary: Capture a snapshot only from a host proven measurable
---

**Arguments.** `[baseline|post] [<target>]`. e.g. /performance:snapshot baseline, /performance:snapshot post

## Purpose

Answers **"what does this cost, and is this machine even able to tell me?"**

Read [`${CLAUDE_PLUGIN_ROOT}/reference/harness-integrity.md`](${CLAUDE_PLUGIN_ROOT}/reference/harness-integrity.md) before writing any harness
here. It is not optional background: a harness that returns a confident wrong answer looks exactly
like one that works, and a check written specifically to avoid being fooled is not exempt.

## Phase order, and why it is this order

### 1. Qualify the host, before measuring anything

The lib is plugin-bundled, not installed, so it needs its directory on `sys.path` before the
import. A bare `from spawn_noise import ...` raises `ModuleNotFoundError` unless the caller happens
to already be in `lib/`. Anchor to the plugin root this body names, which is substituted with the
installed version's directory when the skill loads, rather than to the working directory, a
`__file__` level count, or a hardcoded cache path that breaks on the next plugin version:

```python
import sys

sys.path.insert(0, r"${CLAUDE_PLUGIN_ROOT}/lib")

from spawn_noise import spawn_probe, is_measurable  # noqa: E402

summary = spawn_probe()
measurable, why = is_measurable(summary)
```

`is_measurable()` returns a verdict and its basis. A `False` is a **hard refusal to report a
wall-clock number**, subject only to the recorded override below.

The refusal names what it can still report. That matters: an unexplained refusal gets overridden
reflexively. On a host that fails `is_measurable()`, the durable result is a deterministic spawn
count of 4 -> 1, not a duration.

**Say plainly that this refusal is a house rule.** No surveyed benchmarking tool refuses above a
variance threshold: pyperf, Criterion, JMH and benchstat all warn and print the number anyway.
pyperf's own thresholds (stdev >= 10% of the mean, min/max >= 50% from the mean, shortest value
< 1 ms) are warnings. Presenting this refusal as consensus would be a miscitation.

### 1b. Measuring-tool integrity (before timing)

Before any timed arm runs, record the **measuring tool's identity** for every executable the goal's
metric command names (harness scripts, summarizers, census wrappers): resolved path, `git rev-parse
HEAD` or content hash when the tree is a checkout, and `--version` output when the tool provides it.
Check that **every flag** the goal's metric command uses appears in that copy's `--help` (or is
exercised in a dry run). A stale checkout, wrong plugin root, or missing flag support **stops the
run** and names the fix (update the tool, point at the installed plugin copy, or change the goal's
command). Carry the record in the report:

```text
Tool: <path> @ <rev|hash> (<version>) flags-ok: <yes|no — list missing>
```

### 2. Capture the drift-immune counter first

Spawns, syscalls, queries, allocations, round trips. The counter is the headline; the duration is
context. A counter also catches harness bugs immediately, because a counter that does not move when
it should is an unambiguous signal, while a duration that does not move is ambiguous. Re-measure it
after **every** change.

For a process-spawn count, run the bundled census rather than writing one:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-spawn-census.sh" --shim-dir <stable-dir> --before <cmd>
--after <cmd>`. It takes the rule 1 two-run proof itself and refuses a temporary shim directory,
the harness that once measured its own randomization. `spawn-census.sh` beside it counts one arm.
Report the census as **`spawns=` (PATH-shim accounting)** in the snapshot; when the goal instead
tracks a Windows Job Object or other host counter, state that label explicitly and cite the MSYS
+2-per-external-command rule from
[harness-integrity.md](../../reference/harness-integrity.md#process-counting-on-msyscygwin-git-bash)
so a +2 delta is not chased as a mystery third process.

A deterministic counter needs one run and no statistics; sample counts apply to durations. Under
fixed-tick stepping, the number of units that miss the budget is a counter too, and it beats an
average. See [lab rigs](../../reference/techniques.md#c-lab-measurement-and-rigs).

### 2b. Code path under test (before each arm)

The goal must name which **code path(s)** the metric is meant to exercise (for example skip with no
interpreter versus Python run path, cold cache versus warm). Before **each** arm, either **reset**
the state files that select the path (markers, sentinel files, cache keys) or **record** their
values and carry them in the report. After the arm, report which path actually ran, with evidence
(a marker file, exit code, or the set of processes spawned). Use a line per arm:

```text
Path (<arm>): <intended path from goal> -> <observed path> (evidence: <marker | exit | processes>)
```

An arm whose observed path does not match the goal's named path is **flagged**; its duration is not
reported as the goal's headline metric. A harness that always exercised the rare path while the
common session path stayed unmeasured is exactly the failure this step prevents.

### 3. Capture durations, only if step 1 allowed it

p50 and p95 over at least 20 samples, per the goal. Enforce the arithmetic floor: a percentile `p`
needs `1/(1-p)` samples to be expressible at all (`percentile_floor()` in `lib/spawn_noise.py`).
Report **no** percentile the sample count cannot support; report the raw samples instead.
`${CLAUDE_PLUGIN_ROOT}/scripts/summarize.py` enforces that floor and is what `ab.sh` summarizes
with, so a duration taken through `ab.sh` below already carries it.

Never a single sample. Never a bare mean.

Every duration carries a rig line, because a number without its rig cannot be reproduced:

```text
Rig:  <hardware>, <runtime mode>, <throttling>, <run count>, <timestamp>
```

### 4. Evidence for the goal's `Correlation:` line

Run the same benchmark on two rigs: the counter under the deterministic rig, the duration under
the normal warm runtime. Drive the counter down on at least two independent hot paths (two is this
plugin's judgment) and check that the duration moved with it. A count cut and a time cut differ in
size, so report both and never infer one from the other. No evidence yet means `unproven`, not a
guess. See [prove the proxy](../../reference/techniques.md#d-prove-the-proxy).

## Comparing before and after

**Never compare two separate passes on a drifting host.** A bare `bash -c true` can cost 1825 ms and
283 ms in the same hour on the same machine at ~10% CPU. Any two-pass comparison attributes that 6x
to the change.

Two valid modes:

### Sequential interleaving (default)

Run the bundled harness from the Bash tool; do not hand-roll a timing loop:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ab.sh" --a '<baseline command>' --b '<candidate command>' --iterations 20
```

It alternates the arms within one run, flips the order each iteration, and reports the median of
per-pair ratios (`ratio.py`) alongside per-arm percentiles (`summarize.py`). It also refuses what a
hand-rolled loop gets wrong: an arm whose probe exits 127 (a command that never ran, which a loop
records as a fast clean sample), a drive-letter path in an arm, a ratio from too few pairs, and a
clock it cannot read. `bash "${CLAUDE_PLUGIN_ROOT}/scripts/ab.sh" --help` lists the options.

The paired-ratio median carries its own floor beside the percentile floor: at least 20 pairs, the
default of `${CLAUDE_PLUGIN_ROOT}/scripts/ratio.py`. Below it, report the raw per-pair ratios and no
median, since six repeats of two identical arms at five pairs gave medians from 0.78x to 1.00x and
one run reported 17.12x. A lowered `BENCH_MIN_PAIRS` prints itself on the line; carry it into the
report.

Grounded, Tier 1, `benchstat`'s own documentation: *"The best way to do this is to interleave before
and after runs, rather than running, say, 10 iterations of the before benchmark, and then 10
iterations of the after benchmark."*

**Under uncontrolled concurrent load, suppress the paired ratio** and report per-arm percentiles
only. The arms are no longer load-matched, and pairing by index compares samples that never shared
conditions.

Do not describe this as "paired statistics, per benchstat". `benchstat` recommends interleaved
*collection* and then analyzes with the **Mann-Whitney U test**, which is an independent two-sample
test. It documents no `-delta-test` flag. Verified 2026-09-06 against
`https://pkg.go.dev/golang.org/x/perf/cmd/benchstat` at module version
`v0.0.0-20260819171926-ebcb4798430d`, which documents `-filter`, `-table`, `-row`, `-col`, and
`-ignore`, and states that benchstat uses the Mann-Whitney U-test for A/B comparisons. Recheck when
that page lists a `-delta-test` flag again, or names a test other than Mann-Whitney U.

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

Report the first pass and later passes as separate numbers. A cold first execution folded into warm
repeats hides the cost a first-time user pays.

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

That layout matches `/verification:measure`, which owns baseline capture and storage mechanics, so
the two never keep two different baseline stores. Before capturing, in order:

1. **Check for the seam.** Look for `/verification:measure` in this session's skill list. Record
   whether it resolves; do not assume either answer.
2. **Invoke it, or name why not.** When it resolves, invoke it via the Skill tool. When it resolves
   and you capture directly anyway, the reason goes in the report.
3. **Land the capture under `.work/<topic-slug>/baselines/`.** The path is the gate: a capture
   written anywhere else says so at the top of the report, with the path it used, because a second
   store is the outcome this seam exists to prevent.

The report's header carries exactly one of these lines, so a reader can tell a missing dependency
from a deliberate skip:

```text
Capture: assisted by /verification:measure
Capture: unassisted, verification absent
Capture: unassisted, verification present and skipped because <reason>
```

The dependency is a preference for reuse, not a hard requirement: this skill's own gates (host
qualification, interleaving, the counter, the refusal) work either way, and refusing to measure
because a sibling plugin is missing would be a worse failure than the duplication it avoids.

A counter ceiling that `/performance:protect` checks in is not a baseline: it is a limit on a
deterministic count, and no duration is ever committed.

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
- **A stale harness copy produces plausible wrong numbers.** Record path, revision, and flag support
  before timing; a missing column in the output is too late to catch a nine-commit drift.
- **Report the counter even when the duration is allowed.** The counter is what an independent
  verifier can reproduce tomorrow.
- **Stale markers send every sample down the wrong path.** Reset or record path-selecting state
  before each arm, and report observed path with evidence; a mismatch is flagged, not folded into
  the headline metric.
