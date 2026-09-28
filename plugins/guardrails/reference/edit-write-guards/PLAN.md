# Goal: Edit and Write guardrails fires (#4390)

Target (from /performance:target): the five events in #4390, already measured on
the dotfiles fan-out harness (E1). This file is the `/performance:goal` record.
Baselines stay off the tree; the numbers below were taken on this host on
2026-09-28.

`spawn_probe` (22 samples, `/bin/sh -c exit 0`): min 0.3 ms, median 0.4 ms,
max 0.9 ms, spread 2.71x. `is_measurable` returned True:
"spawn cost spread 2.71x with a 0.3 ms floor: within the measurable band".
S in the table below is `bash -c :`, p50 0.67 ms, p95 0.96 ms, n=22 after 2
warmup. Contention is not the two-part signature (spread under 3x, and the
slow mode is not above 500 ms).

The counter is `scripts/hook-census.sh` field `spawns` (process creations plus
successful execs, the hook's own shell included). It is ranked above the
duration. Correlation on this host: **unproven**. S is under 1 ms, so wall
divided by S is the CPU of sourcing the guards, not the spawn count. On the
Windows host in #4390, S was 20 ms and the process count was the wall.

```text
Metric:     bash scripts/hook-census.sh guardrails <event> <row> <payload> -> spawns
Counter:    spawns (creations + successful execs), ranked above the duration
Correlation: unproven on this host (CPU dominates S). The issue's Windows job-object count is the host where the counter tracks duration.
Boundary:   start: strace attaches to the registered command; end: the hook exits. Cold scratch repo unless the row says --seed. This side of the process split.
Event:      n/a (one dispatcher process per event; peers are not in this metric)
Unit:       n/a
Floor:      shell-form `exit 0` is spawns=1. `exec bash <script>` with no further program is spawns=2 (sh exec plus bash exec, 0 clones). A program the check must start is part of k.
Realistic:  the oracle floor in the table, not a lower number
Ideal:      k × S, k from docs/conventions/hook-budget/README.md
Percentiles: p50, p95 over n=22 (house convention; p95 floor is 20)
Scaling:    n/a for the Bash payload (fixed command). The PostToolUse finding reads git history, which grows with the repo; the deleted-path set is keyed by HEAD and is not re-walked on the warm fire (growth of that walk is 0 across repeats at one HEAD).
Done when:  each row is at or under its ceiling, verdicts on the existing corpus are unchanged, and no row is made async. Merge is in scope. Ideal wall k × S is not the success test: it is below the floor, recorded under Claim.
```

| Event | Census row | Programs (successful execs) | spawns | Wall p50 (direct bash) | k | Ideal |
| --- | --- | --- | ---: | ---: | ---: | --- |
| PreToolUse Bash `git status --short` | `block-no-verify.sh` | sh, bash. 0 clones | 2 | 21.29 ms (31.8 S) | 2 | 2 × S |
| PreToolUse Edit and Write, benign README | `secret-pattern-detection.sh` | sh, bash, grep, 2× git | 13 | 20.32 ms (30.4 S) | 5 execs | 5 × S |
| PostToolUse Edit `.md`, deleted-path finding, cold | `cli-flag-verify.sh` | sh, bash, 5× git | 19 | 23.98 ms (35.8 S) | 7 execs | 7 × S |
| Same finding, second fire at that HEAD | `--seed` | history walk omitted | 13 |  |  |  |
| PostToolUse Edit `.md`, no finding | same row, existing path | sh, bash, 2× git | 9 |  |  |  |
| PostToolUse Edit `.sh` | same row | cli-flag only | 6 |  |  |  |

**Claim:** the ideal wall, k × S, is below the floor of these fires. No further
process can be removed without deleting a check. PreToolUse Bash already starts
no program beyond the shell-form script (spawns=2, creations=0) and still costs
about 21 ms because the dispatcher sources the guards in-process. PostToolUse's
cold finding fire's seven execs are the shell, the dispatcher, and five git
processes: repo root, the tracked list, HEAD, the deleted-path walk, and the
skip-worktree tag. PreToolUse Edit's extra programs are `grep -E` for the secret
oracle and two git queries (`rev-parse`, `check-ignore`). awk, tr, and cut were
incidental and are gone (cold finding 25 → 19, warm 19 → 13).

**Basis:** `scripts/hook-census.sh` on this host after that cut, and the
interleaved wall samples above. `spawn_probe` / `is_measurable` as quoted.
Hook-budget k is the fewest processes for the shape, including each program the
script must start. Async was not used: an async hook's `additionalContext`
arrives on the next turn (hooks reference, re-fetched 2026-09-28; the 0.41.1
note in the README).

**As of:** 2026-09-28.

**Recheck:** a host where S is large enough that wall/S tracks spawns (the
\#4390 Windows harness), or a rewrite that runs the guards without sourcing
`hook-utils.sh`.
