"""Process-spawn noise characterization: is this host measurable at all?

A single spawn timing is misleading because the floor itself moves with machine
load. The same no-op that costs ~120 ms on a drained box costs ~1,100 ms under
contention, and one Windows host was measured at min 180.5 ms / median 1107.7 ms
/ max 2841.3 ms across seven identical no-op spawns. A percentile taken from such
a host is not so much wrong as meaningless in isolation.

So this module reduces repeated no-op spawns to a spread plus a set of findings,
and every reading it emits is labelled with the process count observed at sample
time. A reader cannot mistake a storm-state number for a baseline.

`bimodal-spawn-latency` is the contention signature, and it is a TWO-PART
predicate on purpose: a wide spread whose slow mode is ALSO slow in absolute
terms. A wide ratio alone is not the signature, because on a healthy machine a
cold first spawn against a warm second one clears 3x while every sample is still
fast. Any consumer that re-derives a verdict from `spread_ratio` alone will
report contention on a healthy host.

Python 3.11+, standard library only. Reports; never mutates. Never runs a
discovered hook, statusline command, or MCP server: those are third-party
commands with arbitrary side effects, so timing one by executing it would make
a caller a mutator. Only the no-op baseline below is ever spawned.
"""

from __future__ import annotations

import statistics
import subprocess
import sys
import time

#: Trivial no-op spawns, one per platform. Never a discovered hook or statusline command.
NOOP_SPAWN = {
    "win32": ["cmd", "/c", "exit"],
    "posix": ["/bin/sh", "-c", "exit 0"],
}
SPAWN_SAMPLES = 7
#: A no-op spawn floored above this is already contended before any hook runs.
SLOW_SPAWN_FLOOR_MS = 500.0
#: max/min at or above this across identical no-op spawns is the bimodal contention signature.
BIMODAL_SPREAD_RATIO = 3.0
#: Default ceiling for one no-op spawn. A caller with its own budget passes it explicitly.
SPAWN_TIMEOUT_S = 20


def summarize_spawn_samples(
    durations_ms: list[float], timeouts: int, concurrent_processes: int | None
) -> dict:
    """Reduce repeated no-op spawn timings to min/median/max plus a load label.

    A single spawn number is misleading because the floor itself moves with
    machine load: the same no-op that costs ~120 ms on a drained box costs
    ~1,100 ms under contention. Every reading here is labelled with the process
    count observed at sample time so a reader cannot mistake a storm-state
    number for a baseline.
    """
    result: dict = {
        "samples": len(durations_ms),
        "timeouts": timeouts,
        "concurrent_processes_at_sample": concurrent_processes,
        "state_label": "as-sampled",
        "findings": [],
    }
    if not durations_ms:
        result["findings"].append("no-spawn-samples-captured")
        return result
    low, high = min(durations_ms), max(durations_ms)
    result["min_ms"] = round(low, 1)
    result["median_ms"] = round(statistics.median(durations_ms), 1)
    result["max_ms"] = round(high, 1)
    result["spread_ratio"] = round(high / low, 2) if low > 0 else None
    if low > SLOW_SPAWN_FLOOR_MS:
        result["findings"].append("slow-spawn-floor")
    # A wide RATIO alone is not the contention signature: on a healthy machine a cold
    # first spawn against a warm second one clears 3x while every sample is still fast.
    # The signature is a wide spread whose slow mode is itself slow, so the absolute
    # ceiling has to clear the floor threshold too.
    if (
        result["spread_ratio"] is not None
        and result["spread_ratio"] >= BIMODAL_SPREAD_RATIO
        and high >= SLOW_SPAWN_FLOOR_MS
    ):
        result["findings"].append("bimodal-spawn-latency")
    if timeouts:
        result["findings"].append("spawn-probe-timed-out")
    result["note"] = (
        "The floor moves with load, so compare these numbers only against another capture "
        "carrying a similar concurrent_processes_at_sample. A bimodal spread across identical "
        "no-op spawns IS the contention diagnosis."
    )
    return result


def spawn_probe(samples: int = SPAWN_SAMPLES, timeout_s: float = SPAWN_TIMEOUT_S,
                load_probe=None) -> dict:
    """Time a trivial no-op spawn repeatedly. Never runs a discovered hook.

    This is the baseline every hook, statusline render, and subagent pays before
    it does any work of its own. Timing an actual hook would mean executing a
    third-party command with arbitrary side effects, which this engine will not do.
    """
    command = NOOP_SPAWN["win32"] if sys.platform == "win32" else NOOP_SPAWN["posix"]
    durations: list[float] = []
    timeouts = 0
    for _ in range(samples):
        started = time.perf_counter()
        try:
            subprocess.run(command, capture_output=True, timeout=timeout_s)
        except subprocess.TimeoutExpired:
            timeouts += 1
            durations.append(timeout_s * 1000.0)
            continue
        except OSError:
            break
        durations.append((time.perf_counter() - started) * 1000.0)
    load = load_probe() if load_probe else None
    summary = summarize_spawn_samples(durations, timeouts, load)
    summary["command"] = " ".join(command)
    return summary
