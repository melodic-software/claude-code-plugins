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

The wrapper dominated, and the dominant term inside it was **process creation** — a cost MSYS has
no cheap primitive for. #2521 removed the forks from the per-render path: the tee now writes the
session's payload to a per-session spool file with bash builtins only, and one elected session
drains the spool into the contract snapshot on a cadence (`RLG_TEE_DRAIN_INTERVAL`, default 30 s).
`trace-probe.sh` is the check that the non-elected render path has stayed that way.

Absolute numbers are machine- and window-specific; the thing to hold onto across runs is the
**delta between the two configurations**, bracketed by the spawn floor below.

## Method: the spawn floor

On MSYS every number here is dominated by the cost of creating a process, and that cost drifts
with machine load. Each lane therefore measures the *spawn floor* — the median of 11 bare
`bash -c exit` spawns — **before and after** the timed section, and prints both. A run whose
floor moved materially between the two brackets is not comparable to its neighbour: discard it.
Compare medians, not means; both are printed.

## Lanes

Runnable from a clean checkout — by default every render invokes this repo's
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

# measuring a machine-local entrypoint instead
STATUSLINE_ENTRY="$HOME/.claude/statusline/entrypoint.sh" bash plugins/rate-limit-guard/bench/bench-idle.sh
```

**Isolation:** when a lane exercises the tee, the tee behaves as in production — it spools
per-session records and (in the elected session) drains them into the machine-scope contract file
`~/.claude/rate-limit-guard/rate-limits.json`. On a machine whose loop lanes consume that file,
run the bench against a throwaway HOME so fake `bench-*` sessions never reach real readers:

```shell
HOME="$(mktemp -d)" bash plugins/rate-limit-guard/bench/bench-idle.sh
```

(`trace-probe.sh` always isolates itself this way.)

## Not CI

These are wall-clock benchmarks, not contract tests: on shared CI runners their numbers are
noise, so they gate nothing. None of them use the `*.test.sh` suffix, which is what
`scripts/run-plugin-tests.sh` and the CI test lanes discover — adding or editing files here adds
nothing to CI beyond the usual shell lint gates. The tee's behavioural coverage lives in
`../scripts/statusline-tee.test.sh`.
