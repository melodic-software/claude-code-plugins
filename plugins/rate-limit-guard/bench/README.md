# Statusline render benchmarks

The harness behind the measurements in
[PR #2521](https://github.com/melodic-software/claude-code-plugins/pull/2521)
(`perf(rate-limit-guard): spool the statusline snapshot, drain it on a cadence`, 0.7.0).
It exists so that claim stays reproducible: re-run these lanes before and after any change to the
statusline tee's render path, and compare against the recorded baseline.

## What #2521 measured

Same-window, Windows 11 / MSYS (Git Bash), n=9 sequential renders:

| configuration | per render |
| --- | --- |
| operator's `render.sh` alone | **234.4 ms** |
| the same `render.sh` behind the pre-#2521 tee | **1047.1 ms** |

The wrapper dominated, and the dominant term inside it was **process creation**, a cost MSYS has
no cheap primitive for. #2521 removed the forks from the per-render path: the tee now writes the
session's payload to a per-session spool file with bash builtins only, and one elected session
drains the spool into the contract snapshot on a cadence (`RLG_TEE_DRAIN_INTERVAL`, default 30 s).
`trace-probe.sh` is the check that the non-elected render path has stayed that way.

Absolute numbers are machine- and window-specific; the thing to hold onto across runs is the
**delta between the two configurations**, bracketed by the spawn floor below.

**Instrument note.** The #2521 figures above were taken with the original scratch harness, whose
timer reads ran as `$(command substitution)` subshells, adding roughly one process spawn *inside*
each sample. The committed harness reads the clock with `printf -v` (no fork), so it will report
lower absolute numbers for the same target. The bias was common to both rows of the table, so the
delta that #2521's claim rests on is unaffected. Treat the recorded absolutes as
instrument-inclusive historical values, and re-baseline with the committed harness before using
absolute numbers in a new claim.

## Recorded process counts

`trace-probe.sh --count` reports how many processes one tee render spawns before the wrapped
statusline runs. It counts external commands and bash subshell forks (`$( )`, pipeline elements)
by pid, with `PATH` holding only pid-logging stubs for the externals the tee calls. Process
counts do not move with machine load, so they are the claim to compare across hosts; the
milliseconds below are one host's.

Recorded 2026-09-29 (0.8.36) on WSL2 Linux 6.18, bash 5.3.9, jq 1.8.2, spool path (bash >= 4.2).
No diet was applied, so before and after are the same run:

| render shape | processes spawned, before | after |
| --- | --- | --- |
| non-elected, unchanged input | 0 | 0 |
| non-elected, changed input | 0 | 0 |
| elected drain, snapshot unchanged (no-change skip) | 5 | 5 |
| elected drain, snapshot rewritten | 8 | 8 |
| elected drain, snapshot rewritten, orphan sweep due | 9 | 9 |
| elected drain, first render on a machine | 12 | 12 |

The non-elected render, which is every render but one per `RLG_TEE_DRAIN_INTERVAL` (30 s) per
machine, spawns nothing whether or not its input changed: the payload goes to the session's spool
file with builtins. The elected render pays for the drain (one jq pass, the snapshot write, the
managed-settings read) on that cadence, and the orphan sweep (`find`) on the slower
`RLG_TEE_SWEEP_INTERVAL` (300 s). That meets the 0 to 1 processes per render target on the render
path and confines the rest to the cadence, so the tee needed no diet (#4676).

Wall clock, same host, `bench-idle.sh 21` under a throwaway `HOME`, standalone tee (which adds one
`jq` for its own minimal statusline): median 5 to 6 ms per render, spawn floor 1 ms. Linux
figures are not comparable to Windows/MSYS ones.

Not measured: the synchronous fallback a bash older than 4.2 takes (macOS `/bin/bash` 3.2), which
this host cannot run.

## Method: the spawn floor

On MSYS every number here is dominated by the cost of creating a process, and that cost drifts
with machine load. Each lane therefore measures the *spawn floor*, the median of 11 bare
`bash -c exit` spawns (`BENCH_FLOOR_N` overrides the count), **before and after** the timed
section, and prints both. A run whose floor moved materially between the two brackets is not
comparable to its neighbor: discard it. Compare medians, not means; both are printed.

**Bash floor.** The harness requires **bash >= 5.0** and refuses loudly below it. The tee itself
runs down to bash 3.2 (below 4.2 it degrades to its synchronous path, documented in the
"BASH FLOOR" note in `../scripts/statusline-tee.sh`), but the harness is a measuring instrument whose subject is
process-spawn cost: `EPOCHREALTIME` is the only fork-free clock bash offers, and any fallback
(`date +%s%3N`) would put a spawn inside every timer read. A failing render likewise aborts the
lane. A mistyped `STATUSLINE_ENTRY` must never produce plausible-looking numbers.

## Lanes

Runnable from a clean checkout. By default every render invokes this repo's
`../scripts/statusline-tee.sh` in standalone mode (no wrapped statusline). To measure your real
statusline path, point `STATUSLINE_ENTRY` at the entrypoint your `settings.json` runs (for
the #2521 comparison: once at your render script alone, once at the shim/tee wrapping it).

```shell
# N sequential renders from one idle session (default 11)
bash plugins/rate-limit-guard/bench/bench-idle.sh 9

# SESSIONS concurrent virtual sessions, one render per second for SECONDS (defaults 10, 60)
bash plugins/rate-limit-guard/bench/bench-load.sh 10 60

# xtrace of a non-elected render: everything executed before passthrough
bash plugins/rate-limit-guard/bench/trace-probe.sh

# processes spawned per render shape (portable, unlike wall-clock)
bash plugins/rate-limit-guard/bench/trace-probe.sh --count

# measuring a machine-local entrypoint instead
STATUSLINE_ENTRY="$HOME/.claude/statusline/entrypoint.sh" bash plugins/rate-limit-guard/bench/bench-idle.sh
```

**Isolation:** when a lane exercises the tee, the tee behaves as in production. It spools
per-session records and (in the elected session) drains them into the machine-scope contract file
`~/.claude/rate-limit-guard/rate-limits.json`. On a machine whose loop lanes consume that file,
run the bench against a throwaway HOME so fake `bench-*` sessions never reach real readers:

```shell
HOME="$(mktemp -d)" bash plugins/rate-limit-guard/bench/bench-idle.sh
```

(`trace-probe.sh` always isolates itself this way.)

## CI

The **benchmarks gate nothing**. Wall-clock numbers on shared CI runners are noise, so no lane's
timing ever runs in CI. What does run is `bench.test.sh`, a contract smoke suite discovered by
`scripts/run-plugin-tests.sh` like every other `*.test.sh`, which maps these files into
`scripts/affected-tests.sh` coverage. It splits in two:

- **Every run** unit-tests the lib helpers: `median`, `pace_sleep_arg`, `now_ms` and the refusal
  on a bash without `EPOCHREALTIME`. No lane is spawned, so it costs milliseconds.
- **`BENCH_LANES=1`** adds the lane cases: one tiny-parameter run of each lane against the repo
  tee under an isolated `HOME`, the two failing-render aborts, and the three `--count` cases,
  asserting behavior and output shape, never timing. Spawning a lane is running a benchmark whatever the parameters, so
  those eight cases are gated; without the variable the suite prints a `SKIP:` line and the
  runner's summary names the coverage that did not run.

Run them locally with `BENCH_LANES=1 bash plugins/rate-limit-guard/bench/bench.test.sh`, or in CI
by dispatching `ci.yml` with its `bench_lanes` input set. That is the deliberate run that keeps
the harness runnable from a clean checkout; an unrunnable harness is exactly the defect behind the
unreproducible measurements in #2521. The tee's behavioral coverage lives in
`../scripts/statusline-tee.test.sh`.
