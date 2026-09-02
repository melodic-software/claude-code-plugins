"""Summarize benchmark timings: p50 and p95, plus an exit-code census.

Reads a sample file of `<milliseconds> <exit code>` rows, one per line, and
reports per-arm percentiles.

The rule this file exists to ENFORCE is the arithmetic percentile floor. A
percentile `p` is only expressible from `n` samples when `n >= 1/(1-p)`: below
that, the number a naive interpolation prints is the maximum sample wearing a
percentile's name. So a percentile the sample count cannot support is REFUSED by
name, and the raw samples are printed instead. Reporting the refusal is the
honest answer; reporting the number is not.

Every environment variable is read without a default. A missing one is a caller
bug, and defaulting would silently summarize the wrong file or mislabel an arm.

Environment:
    BENCH_LABEL   arm label for the report line
    BENCH_CONC    concurrency the samples were collected at, for the record
    BENCH_TIMES   path to the sample file

Exit: 0 summarized; 2 a precondition failed.
"""

from __future__ import annotations

import math
import os
import sys
from collections import Counter

import pathfix

REPORTED_PERCENTILES = (50.0, 95.0)


def fail(message: str) -> None:
    print(f"HARNESS FAIL: {message}", file=sys.stderr)
    raise SystemExit(2)


def env(name: str) -> str:
    value = os.environ.get(name)
    if value is None:
        fail(
            f"{name} is not set. This script reads its inputs from the environment "
            f"with no defaults, because a default would silently summarize the wrong "
            f"file or label the wrong arm."
        )
    return value or ""


def percentile_floor(p: float) -> int:
    """Smallest sample count from which percentile `p` is expressible at all."""
    if not 0.0 <= p < 100.0:
        fail(f"percentile {p} is out of range")
    return math.ceil(1.0 / (1.0 - p / 100.0))


def percentile(ordered: list[int], p: float) -> float:
    k = (len(ordered) - 1) * p / 100.0
    lower, upper = math.floor(k), math.ceil(k)
    if lower == upper:
        return float(ordered[lower])
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (k - lower)


def load(path: str) -> tuple[list[int], list[int]]:
    # Resolved rather than opened literally: the caller is a shell that hands
    # this over in an environment variable, and whether MSYS converts a POSIX
    # path there is a heuristic rather than a guarantee. An unconverted /tmp/...
    # would be read against the CURRENT drive root by a native interpreter.
    resolved, note = pathfix.resolve_existing(path)
    if note:
        print(f"NOTE: {note}", file=sys.stderr)
    try:
        with open(resolved, encoding="utf-8") as handle:
            raw = handle.read()
    except OSError as error:
        fail(f"cannot read the sample file {path}: {error}")
        raise  # unreachable; keeps the type checker and the reader honest
    milliseconds: list[int] = []
    codes: list[int] = []
    for number, line in enumerate(raw.splitlines(), start=1):
        if not line.strip():
            continue
        fields = line.split()
        if len(fields) != 2:
            fail(
                f"{path} line {number} is not a `<milliseconds> <exit code>` row: "
                f"{line!r}. A spliced row is what concurrent appends to one sink "
                f"produce, and summarizing it would report a value nothing measured."
            )
        try:
            milliseconds.append(int(fields[0]))
            codes.append(int(fields[1]))
        except ValueError:
            fail(f"{path} line {number} holds a non-integer field: {line!r}")
    return milliseconds, codes


def main() -> int:
    label = env("BENCH_LABEL")
    concurrency = env("BENCH_CONC")
    path = env("BENCH_TIMES")

    milliseconds, codes = load(path)
    if not milliseconds:
        fail(
            f"{path} holds no samples. There is no percentile, mean or minimum to "
            f"report from an empty set, and printing zeroes would read as a result."
        )

    ordered = sorted(milliseconds)
    count = len(ordered)

    cells = []
    refused = False
    for p in REPORTED_PERCENTILES:
        floor = percentile_floor(p)
        if count < floor:
            refused = True
            cells.append(f"p{p:.0f}=REFUSED(n={count}<{floor})")
        else:
            cells.append(f"p{p:.0f}={percentile(ordered, p):.0f}ms")

    print(
        f"{label:<28} conc={concurrency:<3} n={count:<4} "
        f"{' '.join(cells)} "
        f"min={ordered[0]}ms max={ordered[-1]}ms rc={dict(Counter(codes))}"
    )
    if refused:
        print(
            f"{'':<28} raw samples (ms): {' '.join(str(value) for value in ordered)}"
        )
        print(
            f"{'':<28} a percentile p needs 1/(1-p) samples to be expressible; "
            f"below that the printed value is the maximum wearing a percentile's name."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
