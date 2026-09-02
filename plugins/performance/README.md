# performance

Measurement-first optimization for an arbitrary target, built around refusing to report what the
data does not support.

## Why this exists

This plugin was generalized from one end-to-end optimization run done by hand against the
`disk-hygiene` destructive-guard hook (#3523). That session had a competent operator and a strong
initial prompt. It still produced **five verification harnesses that each returned a confident wrong
answer rather than an error**, and every one was caught only because something explicitly re-checked
it:

| Harness | Reported | Actually did |
|---|---|---|
| spawn census via a PATH shim | "no improvement" | `mktemp -d` put a fresh path on `PATH` every run; the subject cached on `PATH`, so every run was a forced cache miss. It measured its own randomization. |
| hard-link identity probe | "0 divergences" | `os.link` failed cross-volume on Windows and fell back to `shutil.copyfile`. A copy is a different file, so the probe never exercised the case it reported on. |
| discrimination check (shell) | "NOT DISCRIMINATING" | A `D:/...` path handed to bash resolves nowhere under MSYS, so both arms exited 127 and the grep found nothing in either. |
| discrimination check (repeat) | "NOT DISCRIMINATING" | Same trap, second harness. |
| discrimination check (python) | "NOT DISCRIMINATING" | Restored via `git checkout --` while the fix under test was uncommitted. The restore silently reverted the fix, so the "with fix" arm ran without it, and the work was destroyed. |

None of those are knowledge gaps. They are all "the measurement was wrong in a way that looked
right", which is what enforced gates prevent and a checklist does not. Four of the five were in
checks written specifically to avoid being fooled: the meta-checks were less reliable than the thing
they were checking.

A workflow that measures without enforcing these rules mostly generates confident numbers, which is
worse than generating none.

## Skills

| Skill | Owns |
|---|---|
| `/performance:target` | Identify and rank candidates by **evidence quality**, not suspicion. Nothing measured yet means the top recommendation is "instrument this first". |
| `/performance:goal` | Human-gated. The metric and the exact command producing it, a **realistic** target and an **ideal** target held separately, and the **floor** computed before any work. |
| `/performance:snapshot` | Host qualification, baseline and post capture, interleaved and duet A/B, the drift-immune counter, and the unmeasurable-host refusal. |
| `/performance:verify` | Fresh-context re-derivation that does not inherit the implementer's numbers, plus the report. |

Each names its successor. There is no router skill.

## What it refuses to do

- **Report a wall-clock claim from a host it has characterized as unmeasurable.** The host this was
  built on spread 15.7x across identical no-op spawns. A percentile from such a host is not so much
  wrong as meaningless in isolation, which is why the durable result in the source PR was a
  deterministic spawn count (4 -> 1) and not a duration. The refusal always names the counter it can
  still report.
- **Rank a duration above a drift-immune counter** when one exists.
- **Compare two separate passes on a drifting host.** A bare `bash -c true` measured 1825 ms and
  283 ms in the same hour at ~10% CPU; any two-pass comparison attributes that 6x to the change.
- **Fold a behavior change into a performance claim.** A correctness regression outranks any
  speedup and is stated separately.
- **Own the fix.** It measures, sets the goal, and verifies. The change itself is delegated to the
  implementation lane.

## Honest about its own grounding

The methodology is sourced (see the source tiers in each skill body), and where the literature does
not support a rule, the skill says so rather than dressing a house choice as consensus:

- **No benchmarking-community sample count for a meaningful percentile exists** beyond the derivable
  `1/(1-p)` floor. The p50/p95-over-20-samples default here is a house rule, and the derivable floor
  is the part that is actually enforced.
- **p95 specifically is convention.** The pattern "median plus a high-order percentile" is grounded
  (Google SRE Book, ch. 4), but the percentiles that chapter names are the 99th and 99.9th.
- **No surveyed tool refuses above a variance threshold.** pyperf, Criterion, JMH and benchstat all
  warn and print anyway. The refusal here is deliberately stricter than the field.
- **The counts-over-wall-clock rationale is grounded only for instruction counts.** Extending it to
  syscalls, queries, and process spawns is this plugin's own generalization, and process-spawn count
  is its headline metric. Valgrind's manual argues both halves itself: execution time "is what users
  perceive", and its simulations are "unlikely to reflect the behaviour of a modern machine".
- **Warmup does not establish steady state.** Barrett et al. (OOPSLA 2017) found at most 43.5% of
  VM/benchmark pairs consistently reach one. Discarding warmup iterations is fine; claiming steady
  state is not.

## Relationship to neighbouring plugins

Every plugin named here is **presence-gated**: this plugin prefers to reuse them, and degrades with a
stated fallback when one is absent. None is a hard install requirement, and none is declared as a
manifest dependency, because a measurement workflow that refuses to run when a sibling plugin is
missing fails worse than the duplication it was avoiding.

- **`/verification:measure`** owns two-phase baseline/compare and machine-bound baseline storage.
  When the `verification` plugin is installed this plugin reuses it rather than reimplementing it,
  and adds what it does not cover: interleaved A/B, drift-immune counters, host-unmeasurability
  refusal, precondition-asserting probes, and goal tiers. When it is absent, baselines are captured
  into the same memory-tier path directly and the report says the capture was unassisted.
- **`/claude-ops:audit-performance`** diagnoses a slow *Claude Code installation*. This plugin
  optimizes an *arbitrary target*. They share the noise characterization through
  `lib/spawn_noise.py`, which each plugin **carries its own byte-identical copy of** as a registered
  cross-plugin cluster. Neither imports the other at runtime, since plugins install independently;
  the sync gate is what keeps the bimodal threshold at exactly one home.
- **`/implementation:implement`** owns the change. This plugin does not.

## Baselines

Baselines live in the topic's memory tier (`.work/<topic-slug>/baselines/`), are machine-bound, and
are **never committed**, matching `/verification:measure`. A committed baseline is a number that
outlives the conditions that made it true.
