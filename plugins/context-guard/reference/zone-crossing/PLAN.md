# Goal: PostToolBatch zone-crossing, no-crossing path (#4392)

Target (from /performance:target): `zone-crossing-inject.sh` on PostToolBatch,
measured in #4392 (E1: 5 processes, median about 90–110 ms at S = 20 ms). This
file is the `/performance:goal` record.

`spawn_probe` (22 samples, `/bin/sh -c exit 0`): min 0.3 ms, median 0.4 ms,
max 0.9 ms, spread 2.71x. `is_measurable` returned True:
"spawn cost spread 2.71x with a 0.3 ms floor: within the measurable band".
S is `bash -c :`, p50 0.77 ms, p95 1.08 ms, n=22 after 2 warmup.

```text
Metric:     bash scripts/hook-census.sh context-guard PostToolBatch zone-crossing-inject.sh <same-zone payload> -> spawns
            plus direct `bash hooks/zone-crossing-inject.sh` wall, p50 and p95, n=22
Counter:    child process creations (clone/fork/vfork that are not threads). Ranked above the duration. Census spawns is the exec-form accounting of the same fire (node, then bash).
Correlation: on this host the no-crossing path's wall moved with the library source (about 10 S down to 2.88 S) while child creations stayed 0. The counter and the duration agree that the resolver is not the cost.
Boundary:   start: the hook process begins; end: it exits 0 with empty stdout. Warm state: a fresh captured_at, same snapshot body, mark and inputs already written. This side of any resolver split; the resolver is not started.
Event:      PostToolBatch wall for this hook. Peers on the event are not in the metric.
Unit:       zone-crossing-inject.sh. Marginal cost is this hook's own wall; it does not wait on another context-guard hook.
Floor:      empty `bash -c :` p50 0.77 ms (1 S). Parsing this file and exiting immediately measured 0.82 ms. The no-crossing body measured p50 2.21 ms.
Realistic:  p50 <= 4 × S and p95 <= 5 × S, and 0 child processes
Ideal:      1 × S (one process, no incidental source, no child)
Percentiles: p50, p95 over n=22 (house convention)
Scaling:    the same-zone body does not read the transcript. The payload is read once. An oversize envelope whose ids precede tool_calls still exits with 0 child processes (the suite's oversize case).
Done when:  census spawns <= 3 with creations = 1 (node starting bash, no resolver), direct-bash wall inside the realistic band, and crossing injection text unchanged. Merge is in scope.
Target (from /performance:target): zone-crossing-inject PostToolBatch no-crossing path @ E1
```

Measured after `hook-utils.sh` stays unloaded until a crossing or an unproved payload:

| Arm | p50 | p95 | vs S p50 0.77 ms |
| --- | ---: | ---: | --- |
| `bash -c :` | 0.77 ms | 1.08 ms | 1 S |
| same-zone rewrite, direct bash | 2.21 ms | 2.88 ms | 2.88 S / 3.74 S |
| mark newer than the snapshot, direct bash | 2.23 ms | 2.45 ms | 2.91 S / 3.18 S |
| census `spawns` | 3 |  | creations=1, execs=2 (main before this change: 7, creations=3) |

**Claim:** the script's no-crossing path starts no child. Census reports 3 because
the registered row is exec form `node exec-bash.mjs <script>`: node starts bash
and bash creates nothing else. Direct `bash` of the script is one exec and zero
forks. Ideal 1 × S is the empty process. The realistic band is 4 × S / 5 × S
because proving the session id and comparing the snapshot are builtins in this
file; sourcing `hook-utils.sh` (about 5.4 ms, the previous 10 S) is not part of
that floor.

**Basis:** `scripts/hook-census.sh` ceiling row
`context-guard-posttoolbatch-same-zone-rewrite-spawns`, the wall samples above,
and `plugins/context-guard/hooks/zone-crossing-inject.test.sh` (PASS=112),
including the strace budget of 0 forks on the steady path and 2 forks only when
the resolver runs.

**As of:** 2026-09-28.

**Recheck:** the hooks reference grows a placeholder that names an interpreter,
so this row can run bash without node in front, or `hook-utils.sh`
shrinks enough that sourcing it is cheaper than the builtin scan.
