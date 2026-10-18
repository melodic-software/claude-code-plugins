#!/usr/bin/env python3
"""Drop pr-merge candidates the gate refuses on their list payload alone.

pr-merge.yml lists candidates with their labels and body, then runs the gate
once per candidate; each gate run spends tens of lane-token calls before it
refuses a held pull request. A hold the gate reads from the same fields (the
hold label (`UNATTENDED_HOLD_LABELS`) or a body hold, `babysit_merge.evaluate`) refuses
whatever else the gate finds, so this drops such a candidate before the gate
starts. It makes no API call. The gate still checks every hold itself.

When every candidate is held, one stays, so a gate process still sweeps the
merge queue and dequeues any held entry the identity queued.

Reads a JSON array of {number, head, updatedAt, labels, body} on stdin and
prints {"candidates": [...], "held": [...]}: the kept candidates as {number,
head, updatedAt}, the dropped ones with their `reason` added.
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from babysit_merge import BODY_MERGE_HOLD_RE, merge_hold_label

FIELDS = ("number", "head", "updatedAt")


def hold(candidate: dict[str, Any]) -> str | None:
    """The hold the gate refuses this candidate on, named as `entry_hold`
    names it, or None."""
    if held_by := merge_hold_label(candidate.get("labels") or [], unattended=True):
        return held_by
    if BODY_MERGE_HOLD_RE.search(str(candidate.get("body") or "")):
        return "body-hold"
    return None


def split(candidates: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    kept: list[dict[str, Any]] = []
    held: list[dict[str, Any]] = []
    for candidate in candidates:
        row = {k: candidate.get(k) for k in FIELDS}
        if reason := hold(candidate):
            held.append({**row, "reason": reason})
        else:
            kept.append(row)
    if not kept and held:
        first = held.pop(0)
        kept.append({k: first[k] for k in FIELDS})
    return {"candidates": kept, "held": held}


def main(argv: list[str] | None = None) -> int:
    argparse.ArgumentParser(description=__doc__, allow_abbrev=False).parse_args(argv)
    print(json.dumps(split(json.load(sys.stdin))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
