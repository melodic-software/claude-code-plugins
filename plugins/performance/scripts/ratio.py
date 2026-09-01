"""Paired-sample ratio for an interleaved A/B run.

The absolute numbers on a drifting host move several-fold within an hour, so the
per-iteration PAIRED ratio is the statistic that survives: each pair was taken
back to back under the same instantaneous load. The median of the per-pair
ratios is reported alongside the ratio of medians, because a single drift spike
moves the latter and not the former.

Two refusals are ENFORCED here, in this file, rather than left to the caller:

1. Under concurrency the paired ratio is SUPPRESSED. Once the arms overlap they
   interleave arbitrarily, so pairing by index compares samples that never
   shared conditions. Per-arm percentiles are the honest statistic there.
   BENCH_CONC is read with no default precisely so a caller who forgets it gets
   an error rather than a silently re-enabled ratio.

2. Arms of unequal length are refused outright. Pairing by index across unequal
   arms silently drops the tail of the longer arm and reports a ratio over a
   sample set nobody chose.

3. EVERY ratio on the line is refused below a minimum pair count, the same way
   summarize.py refuses a percentile the sample count cannot express. Measured on
   the host this was built for, six repeats of two IDENTICAL arms at five
   iterations produced median paired ratios of 1.00, 0.96, 0.85, 1.00, 0.78 and
   0.98, and one run reported 17.12x. BENCH_MIN_PAIRS overrides the default of
   20, which is the plugin's house sample count rather than a derived floor, and
   a lowered floor prints itself on the line.

   The gate covers `ratio_of_p50` and `ratio_of_p95` too, not just the headline.
   Gating only the headline left two quotable numbers sitting beside an honest
   one: two IDENTICAL `true` arms at twenty iterations reported
   `median_paired_ratio=1.06x ratio_of_p50=12.08x ratio_of_p95=0.35x`, and a
   reader quotes whichever number is printed.

4. A ZERO DENOMINATOR is refused rather than clamped. Dividing by
   `max(percentile(new, p), 1.0)` turned an arm the clock could not resolve into
   a 1ms denominator and manufactured a ratio out of the clamp. That, not drift,
   is where the 12.08x above came from.

5. When the paired median and the ratio of medians DISAGREE beyond a stated
   factor, the line says so. One of them is drift, and nothing else in the output
   tells the reader which.

Do not describe this output as "paired statistics, per benchstat". benchstat
recommends interleaved COLLECTION and then analyses with the Mann-Whitney U
test, which is an independent two-sample test.

Environment:
    BENCH_OLD        sample file for the baseline arm
    BENCH_NEW        sample file for the comparison arm
    BENCH_CONC       concurrency the samples were collected at
    BENCH_MIN_PAIRS  optional; minimum pairs before a ratio is reported (default 20)

Exit: 0 reported or suppressed; 2 a precondition failed.
"""

from __future__ import annotations

import math
import os
import statistics
import sys

import pathfix

LABEL_WIDTH = 28
DEFAULT_MIN_PAIRS = 20
# Two ratios of the same two arms disagreeing by this much means one of them is
# drift rather than signal. A house threshold, not a derived one, and it is
# stated as such in the output it produces.
DISAGREEMENT_FACTOR = 2.0


def fail(message: str) -> None:
    print(f"HARNESS FAIL: {message}", file=sys.stderr)
    raise SystemExit(2)


def env(name: str) -> str:
    value = os.environ.get(name)
    if value is None:
        fail(
            f"{name} is not set. It is read with no default on purpose: defaulting "
            f"BENCH_CONC to 1 would re-enable the paired ratio under concurrency for "
            f"any caller who forgot to pass it."
        )
    return value or ""


def load(path: str) -> list[int]:
    # Resolved rather than opened literally, for the reason summarize.py records:
    # whether MSYS converts a POSIX path carried in an environment variable is a
    # heuristic, not a guarantee.
    resolved, note = pathfix.resolve_existing(path)
    if note:
        print(f"NOTE: {note}", file=sys.stderr)
    try:
        with open(resolved, encoding="utf-8") as handle:
            raw = handle.read()
    except OSError as error:
        fail(f"cannot read the sample file {path}: {error}")
        raise  # unreachable
    values: list[int] = []
    for number, line in enumerate(raw.splitlines(), start=1):
        if not line.strip():
            continue
        # The SAME row shape summarize.py enforces, deliberately duplicated rather
        # than relaxed. This file documents that a caller invoking it directly
        # cannot lose the concurrency suppression; a row guard that only
        # summarize.py applied would be a hole in exactly that promise, and a
        # spliced row from concurrent appends parses as a plausible number.
        fields = line.split()
        if len(fields) != 2:
            fail(
                f"{path} line {number} is not a `<milliseconds> <exit code>` row: "
                f"{line!r}. A spliced row is what concurrent appends to one sink "
                f"produce, and pairing it would report a ratio over a value nothing "
                f"measured."
            )
        try:
            values.append(int(fields[0]))
        except ValueError:
            fail(f"{path} line {number} has no leading integer milliseconds: {line!r}")
    return values


def percentile_floor(p: float) -> int:
    return math.ceil(1.0 / (1.0 - p / 100.0))


def percentile(values: list[int], p: float) -> float:
    ordered = sorted(values)
    k = (len(ordered) - 1) * p / 100.0
    lower, upper = math.floor(k), math.ceil(k)
    if lower == upper:
        return float(ordered[lower])
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (k - lower)


def ratio_of_percentile(
    old: list[int], new: list[int], p: float, pairs_count: int, minimum: int
) -> tuple[str, float | None]:
    """Return (cell, value). `value` is None whenever the ratio was refused.

    THREE gates, and every one of them was a way to print a number the data does
    not support:

    1. The MINIMUM PAIR COUNT, the same gate the headline ratio carries. A ratio
       of two per-arm percentiles compounds the drift in both, so it is if
       anything less stable than the paired median, and gating only the headline
       left two quotable numbers beside an honest one. Measured here, two
       IDENTICAL `true` arms at twenty iterations reported ratio_of_p50=12.08x.
    2. The percentile ARITHMETIC floor, 1/(1-p).
    3. A ZERO DENOMINATOR. This is where that 12.08x actually came from: the
       previous code divided by `max(percentile(new, p), 1.0)`, so an arm whose
       percentile was 0ms silently became 1ms and manufactured a ratio out of a
       clamp. A sub-millisecond denominator does not mean "one millisecond", it
       means the clock cannot resolve this arm, and the honest output is a
       refusal naming that.
    """
    label = f"ratio_of_p{p:.0f}"
    if pairs_count < minimum:
        return f"{label}=REFUSED(pairs={pairs_count}<{minimum})", None
    floor = percentile_floor(p)
    if len(old) < floor:
        return f"{label}=REFUSED(n={len(old)}<{floor})", None
    denominator = percentile(new, p)
    if denominator <= 0:
        return f"{label}=REFUSED(comparison p{p:.0f}=0ms, below clock resolution)", None
    value = percentile(old, p) / denominator
    return f"{label}={value:.2f}x", value


def main() -> int:
    concurrency = env("BENCH_CONC")
    if concurrency != "1":
        print(
            f"{'SPEEDUP':<{LABEL_WIDTH}} SUPPRESSED: concurrency={concurrency}. "
            f"Under uncontrolled concurrent load the arms are no longer load-matched, "
            f"so pairing by index compares samples that never shared conditions. "
            f"Read the per-arm percentiles above instead."
        )
        return 0

    old = load(env("BENCH_OLD"))
    new = load(env("BENCH_NEW"))

    if not old or not new:
        fail("at least one arm holds no samples; there is no ratio to report.")
    if len(old) != len(new):
        fail(
            f"the arms hold {len(old)} and {len(new)} samples. A paired ratio pairs by "
            f"index, so unequal arms would silently drop the longer arm's tail and "
            f"report a ratio over a sample set nobody chose."
        )

    pairs = [(o, n) for o, n in zip(old, new) if n > 0]
    dropped = len(old) - len(pairs)
    if not pairs:
        fail(
            "every comparison-arm sample was zero milliseconds, so no per-pair ratio "
            "is defined. The clock resolution is coarser than the subject; measure a "
            "larger unit of work."
        )

    ratios = [o / n for o, n in pairs]
    note = f" dropped={dropped}(zero-ms comparison samples)" if dropped else ""

    minimum_raw = os.environ.get("BENCH_MIN_PAIRS", str(DEFAULT_MIN_PAIRS))
    try:
        minimum = int(minimum_raw)
    except ValueError:
        fail(f"BENCH_MIN_PAIRS must be an integer, got {minimum_raw!r}")
        raise  # unreachable

    # A LOWERED floor records itself on the reported line. A gate that can be
    # quietly relaxed is not a gate: without this, BENCH_MIN_PAIRS=1 prints a
    # headline ratio indistinguishable from one drawn from a full sample set, and
    # the reader has no way to know the floor moved.
    override = ""
    if minimum < DEFAULT_MIN_PAIRS:
        override = f"  OVERRIDE: min_pairs={minimum} (default {DEFAULT_MIN_PAIRS})"

    p50_cell, p50_value = ratio_of_percentile(old, new, 50.0, len(pairs), minimum)
    p95_cell, _ = ratio_of_percentile(old, new, 95.0, len(pairs), minimum)

    if len(pairs) < minimum:
        # EVERY ratio on the line is refused below the floor, not just the
        # headline. A reader quotes whichever number is printed, so leaving the
        # subordinate two ungated beside a refused headline is the same defect
        # wearing a smaller label.
        print(
            f"{'SPEEDUP':<{LABEL_WIDTH}} "
            f"median_paired_ratio=REFUSED(pairs={len(pairs)}<{minimum})  "
            f"{p50_cell}  {p95_cell}{note}"
        )
        print(
            f"{'':<{LABEL_WIDTH}} raw per-pair ratios: "
            f"{' '.join(f'{value:.2f}' for value in ratios)}"
        )
        print(
            f"{'':<{LABEL_WIDTH}} two IDENTICAL arms measured here spread 0.78x to 17.12x "
            f"at five pairs. Raise the iteration count, or lower BENCH_MIN_PAIRS "
            f"deliberately and say so in the report."
        )
        return 0

    median_paired = statistics.median(ratios)

    # The docstring predicts that a drift spike moves the ratio of medians and
    # not the paired median. Predicting it is not enough: when the two disagree
    # this far, one of them is noise, and the reader has no way to tell which
    # unless the line says so.
    disagreement = ""
    if p50_value is not None and min(median_paired, p50_value) > 0:
        spread = max(median_paired, p50_value) / min(median_paired, p50_value)
        if spread >= DISAGREEMENT_FACTOR:
            disagreement = (
                f"  DISAGREEMENT: paired median and ratio-of-p50 differ by {spread:.1f}x. "
                f"They measure the same thing, so one is drift. Trust the paired median; "
                f"it is the only one whose samples shared conditions."
            )

    print(
        f"{'SPEEDUP':<{LABEL_WIDTH}} pairs={len(pairs):<4} "
        f"median_paired_ratio={median_paired:.2f}x  "
        f"{p50_cell}  {p95_cell}{note}{override}{disagreement}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
