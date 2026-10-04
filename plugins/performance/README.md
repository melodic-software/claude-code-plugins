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
| discrimination check (shell) | "NOT DISCRIMINATING" | A Windows path spelling handed to bash left both arms exiting 127, so neither arm ever reached the subject and the grep found nothing in either. |
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
| `/performance:protect` | Locks in a proven counter win: a checked-in counter ceiling, a CI check that fails when the counter rises, and a lower ceiling when it falls: in the same PR, or through a scheduled draft PR for a counter that can fall without a code change. Never merges. |
| `/performance:go-faster` | Whole-process sweep for ways to go faster without losing accuracy: checks 16 areas, ranks evidenced findings, and offers session changes for adoption. |

Each names its successor. There is no router skill, and go-faster sweeps and ranks but does not
drive the goal, snapshot, verify and protect loop. The loop over the five skills runs under the
user's own `/goal` or `/loop` condition, which sets its cadence and when it stops.

- **Pointer**: when you want a per-goal optimization loop run end to end, fetch the post's [The loop, thread by thread section](https://claude.dev/blog/how-we-made-claude-ai-faster/#the-loop-thread-by-thread) live; no docs page covers a per-goal optimization loop as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering a per-goal loop.

Each `SKILL.md` frontmatter carries `metadata.workflow-stage` and `metadata.summary`. Claude Code
does not act on `metadata`; both keys are read by the marketplace's own
[`scripts/generate-cheatsheet.mjs`](../../scripts/generate-cheatsheet.mjs), which places each skill
in a stage and prints its summary in [`docs/skill-cheat-sheet.md`](../../docs/skill-cheat-sheet.md).

## Reference

- [`reference/techniques.md`](reference/techniques.md): the technique catalog, by loop phase. Each
  skill step points at the section it uses.
- [`reference/glossary.md`](reference/glossary.md): the terms the skills and the catalog use.
- [`reference/harness-integrity.md`](reference/harness-integrity.md): the rules a harness must
  satisfy before any number it produces is reported.

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
- **Own the fix.** It measures, sets the goal, and verifies; the edit itself is delegated to
  `/implementation:implement`. A run from goal through verify, the fix included, is driven by the
  user's own `/goal` or `/loop` condition, whose turn clause bounds it.

## Honest about its own grounding

Each skill body names its source tiers. Where a rule is a house choice, the bullet below says so
rather than presenting it as consensus:

- **The sample count is a house rule.** The p50/p95-over-20-samples default is this plugin's choice;
  the derivable `1/(1-p)` floor is the part that is actually enforced.
- **p95 is this plugin's choice.** The plugin reports a median beside one high-order percentile, and
  picks p95 as that percentile.
  - **Pointer**: when choosing which high-order percentile to report, fetch the Google SRE Book's [Aggregation section](https://sre.google/sre-book/service-level-objectives/#aggregation-1Ls9hQin) live. **As of**: 2026-10-02. **Recheck trigger**: that section changes the percentiles it discusses.
- **The variance refusal is this plugin's rule.** The harness refuses to report above its variance
  threshold rather than warning and printing.
- **Counting over wall-clock time is this plugin's rule for every counter.** It applies the rule to
  instruction counts, syscalls, queries and process spawns, and process-spawn count is its headline
  metric.
  - **Pointer**: when weighing instruction counts against execution time, fetch the Cachegrind manual's [Overview](https://valgrind.org/docs/manual/cg-manual.html#cg-manual.overview) live. **As of**: 2026-10-02. **Recheck trigger**: a Valgrind release changes that section.
- **Warmup does not establish steady state.** Discarding warmup iterations is fine; claiming steady
  state is not.
  - **Pointer**: when checking how often benchmarks reach a steady state, fetch Barrett et al., [Virtual Machine Warmup Blows Hot and Cold](https://doi.org/10.1145/3133876) (OOPSLA 2017) live. **As of**: 2026-10-02. **Recheck trigger**: a later study revises that finding.

## Relationship to neighboring plugins

Every plugin named here is **presence-gated**: this plugin prefers to reuse them, and degrades with a
stated fallback when one is absent. None is a hard install requirement, and none is declared as a
manifest dependency, because a measurement workflow that refuses to run when a sibling plugin is
missing fails worse than the duplication it was avoiding.

- **`/verification:measure`** owns two-phase baseline/compare and machine-bound baseline storage.
  When the `verification` plugin is installed this plugin reuses it rather than reimplementing it,
  and adds what it does not cover: interleaved A/B, drift-immune counters, host-unmeasurability
  refusal, precondition-asserting probes, and goal tiers. When it is absent, baselines are captured
  into the same memory-tier path directly and the report says the capture was unassisted.
- **`/harness-ops:audit-performance`** diagnoses a slow *Claude Code installation*. This plugin
  optimizes an *arbitrary target*. They share the noise characterization through
  `lib/spawn_noise.py`, which each plugin **carries its own byte-identical copy of** as a registered
  cross-plugin cluster. Neither imports the other at runtime, since plugins install independently;
  the sync gate is what keeps the bimodal threshold at exactly one home.
- **`/implementation:implement`** owns the change. This plugin does not.

## Baselines

Durations are never committed; a counter ceiling for `/performance:protect` may be. Baselines live
in the topic's memory tier (`.work/<topic-slug>/baselines/`) and are machine-bound, matching
`/verification:measure`. A committed duration is a number that outlives the conditions that made it
true. A ceiling on a deterministic counter does not drift with host load, which is why it is the one
number that is checked in.
