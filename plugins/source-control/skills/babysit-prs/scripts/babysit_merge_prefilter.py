#!/usr/bin/env python3
"""Drop pr-merge candidates the gate refuses on their list payload alone.

pr-merge.yml lists candidates with their labels and body, then runs the gate
once per candidate; each gate run spends tens of lane-token calls before it
refuses a held pull request. A hold the gate reads from the same fields (a
hold label, the human-gated one included, or a body hold,
`babysit_merge.evaluate`) refuses whatever else the gate finds, so this drops such a candidate before the gate
starts. It makes no API call. The gate still checks every hold itself.

When every candidate is held, one stays, so a gate process still sweeps the
merge queue and dequeues any held entry the identity queued.

`--human-gated` names the tracker's human-gated role label, resolved by the
caller as `babysit_postmerge._role_label` resolves it (default `needs-human`).
Candidates come out CLEAN first (their `mergeStateStatus`), then oldest
`createdAt` first, so a sweep the job timeout cuts short has tried the ones
likeliest to merge. A candidate without `mergeStateStatus` is not CLEAN, and
one without `createdAt` sorts last in its group, so input without either field
keeps its order after every dated one. The order changes nothing the gate
decides.

Reads a JSON array of {number, head, updatedAt, labels, body, createdAt,
mergeStateStatus} on stdin and prints {"candidates": [...], "held": [...]}:
the kept candidates as {number, head, updatedAt}, the dropped ones with their
`reason` added.
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from babysit_merge import BODY_MERGE_HOLD_RE, merge_hold_label
from babysit_postmerge import DEFAULT_ROLE_LABEL

FIELDS = ("number", "head", "updatedAt")


def hold(
    candidate: dict[str, Any], human_gated: str = DEFAULT_ROLE_LABEL
) -> str | None:
    """The hold the autonomous gate refuses this candidate on, named as
    `entry_hold` names it, or None."""
    labels = candidate.get("labels") or []
    if held_by := merge_hold_label(labels, human_gated=human_gated):
        return held_by
    if BODY_MERGE_HOLD_RE.search(str(candidate.get("body") or "")):
        return "body-hold"
    return None


def sweep_order(candidate: dict[str, Any]) -> tuple[bool, bool, str]:
    """CLEAN first, then oldest `createdAt`; no `createdAt` sorts last in its group."""
    created = str(candidate.get("createdAt") or "")
    return candidate.get("mergeStateStatus") != "CLEAN", not created, created


def split(
    candidates: list[dict[str, Any]], human_gated: str = DEFAULT_ROLE_LABEL
) -> dict[str, list[dict[str, Any]]]:
    kept: list[dict[str, Any]] = []
    held: list[dict[str, Any]] = []
    for candidate in sorted(candidates, key=sweep_order):
        row = {k: candidate.get(k) for k in FIELDS}
        if reason := hold(candidate, human_gated):
            held.append({**row, "reason": reason})
        else:
            kept.append(row)
    if not kept and held:
        first = held.pop(0)
        kept.append({k: first[k] for k in FIELDS})
    return {"candidates": kept, "held": held}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument(
        "--human-gated",
        default=DEFAULT_ROLE_LABEL,
        help="the tracker's human-gated role label (default %(default)s)",
    )
    args = parser.parse_args(argv)
    print(
        json.dumps(
            split(json.load(sys.stdin), args.human_gated.strip() or DEFAULT_ROLE_LABEL)
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
