#!/usr/bin/env python3
"""Compute merge.max-in-flight from merge.in-flight-sizing in pr-pipeline.yaml.

    python3 -I scripts/compute-max-in-flight.py          print the computed cap
    python3 -I scripts/compute-max-in-flight.py --check  exit 1 if the set value differs

The formula is stated beside its inputs in the YAML; change an input, run this, and set
`max-in-flight` to what it prints. test_compute_max_in_flight.py runs `--check`.
"""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "plugins/source-control/skills/babysit-prs/scripts"))

import babysit_risk  # noqa: E402

CONFIG = ROOT / "docs/conventions/pr-pipeline.yaml"
INPUTS = (
    "peak-merges-per-hour",
    "mean-minutes-in-flight",
    "app-hourly-limit",
    "app-target-percent",
    "app-peak-hourly-used",
    "app-calls-per-candidate",
    "reader-runs-per-hour",
)


def cap(sizing: dict[str, int]) -> int:
    """The smaller of the peak rate over the time in flight and what the
    lanes App's hourly target leaves for candidate reads; at least 1."""
    rate = -(-sizing["peak-merges-per-hour"] * sizing["mean-minutes-in-flight"] // 60)
    spare = (
        sizing["app-hourly-limit"] * sizing["app-target-percent"] // 100
        - sizing["app-peak-hourly-used"]
    )
    budget = spare // (
        sizing["reader-runs-per-hour"] * sizing["app-calls-per-candidate"]
    )
    return max(1, min(rate, budget))


def read(path: pathlib.Path) -> tuple[str | None, dict[str, int]]:
    """The set value and the integer inputs; a missing input raises KeyError."""
    entries = dict(babysit_risk._yaml_entries(path.read_text(encoding="utf-8")))
    sizing = {key: int(entries["merge", "in-flight-sizing", key]) for key in INPUTS}
    return entries.get(("merge", "max-in-flight")), sizing


def main(argv: list[str], path: pathlib.Path = CONFIG) -> int:
    try:
        value, sizing = read(path)
    except (KeyError, ValueError) as exc:
        print(
            f"merge.in-flight-sizing input missing or not a whole number: {exc}",
            file=sys.stderr,
        )
        return 1
    computed = cap(sizing)
    if "--check" not in argv:
        print(computed)
        return 0
    if value == str(computed):
        return 0
    print(
        f"merge.max-in-flight is {value}; merge.in-flight-sizing computes {computed}",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
