#!/usr/bin/env python3
"""Merge the clone pairs a detector reports into clone classes.

    cluster-clones.py [--root <dir>] [< report.json]

Reads a `code-metrics/v1` document on stdin and prints it back with the
two-instance clone-group rows that share an identical instance merged into one
row per clone class. jscpd (both majors) and PMD CPD report a clone as a PAIR,
so N byte-identical copies of one fragment arrive as N-1 rows that all name
the same instance of the first copy, and a summary derived from those rows
would count the fragment's lines N-1 times. A clone class is the union of
every pair that shares a code portion (Roy and Cordy 2007 s.6, citing Rieger,
Ducasse and Lanza 2004; Roy, Cordy and Koschke 2009 aggregate pairs into
classes in post-processing), and that closure is exact for the byte-identical
clones a token detector reports.

Two rows join when they share an instance with identical `(file, start_line,
end_line)` and equal `values.lines`. Overlap is not enough: a pair whose
shared file is named with a different range (a third copy that carries only
part of the fragment) stays its own group, so a class is never widened past
what the detector said was identical. The merged row keeps the first row's
`values`, so the fragment's lines count once, carries the union of the
instances sorted by `(file, start_line)`, and appends `clustered` to `labels`.
The sort compares each file made relative to `--root` (the instance keeps the
path the detector gave it), so the first instance, and the directory the
report's rollup attributes the class to, is the same whichever directory the
run started from; without `--root` the paths sort as given.
A row with three or more instances is already a class and passes through, as
does every row without `instances`, and every row keeps its position. Rows
join whatever their `collector`, so a pair another detector reported merges
too. `summary` is left alone: the caller recomputes it with `report.py
resummarize`.

Exit 0 when the document was printed, 2 when stdin is not a JSON document.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts"))
from pathglob import root_relative  # noqa: E402

MIN_PYTHON = (3, 9)
LABEL = "clustered"


def instance_key(instance: dict[str, Any]) -> tuple[str, Any, Any]:
    return (
        str(instance.get("file", "")).replace("\\", "/"),
        instance.get("start_line"),
        instance.get("end_line"),
    )


def _sort_key(instance: dict[str, Any], root: str) -> tuple[str, int]:
    start = instance.get("start_line")
    return (
        root_relative(instance_key(instance)[0], root),
        start if isinstance(start, int) else -1,
    )


def _is_pair(row: dict[str, Any]) -> bool:
    instances = row.get("instances")
    return isinstance(instances, list) and len(instances) == 2


def cluster(measures: list[dict[str, Any]], root: str = "") -> list[dict[str, Any]]:
    """Return `measures` with pair rows that share an identical instance merged."""
    parent: dict[int, int] = {
        index: index for index, row in enumerate(measures) if _is_pair(row)
    }

    def find(index: int) -> int:
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    def union(left: int, right: int) -> None:
        left, right = find(left), find(right)
        if left != right:
            # The lower index stays the root, so a class is emitted where its
            # first pair stood and its `values` are that first pair's.
            parent[max(left, right)] = min(left, right)

    seen: dict[tuple[Any, ...], int] = {}
    for index in parent:
        row = measures[index]
        lines = (row.get("values") or {}).get("lines")
        for instance in row["instances"]:
            key = (instance_key(instance), lines)
            if key in seen:
                union(seen[key], index)
            else:
                seen[key] = index

    members: dict[int, list[int]] = {}
    for index in parent:
        members.setdefault(find(index), []).append(index)

    output: list[dict[str, Any]] = []
    for index, row in enumerate(measures):
        if index not in parent:
            output.append(row)
            continue
        leader = find(index)
        if leader != index:
            continue
        group = members[leader]
        if len(group) == 1:
            output.append(row)
            continue
        instances: dict[tuple[str, Any, Any], dict[str, Any]] = {}
        for member in group:
            for instance in measures[member]["instances"]:
                instances.setdefault(instance_key(instance), instance)
        merged = dict(row)
        merged["instances"] = sorted(
            instances.values(), key=lambda instance: _sort_key(instance, root)
        )
        labels = [str(label) for label in row.get("labels") or []]
        if LABEL not in labels:
            labels.append(LABEL)
        merged["labels"] = labels
        output.append(merged)
    return output


def main(argv: list[str]) -> int:
    root = ""
    if argv == ["--root"] or (argv and argv[0] != "--root") or len(argv) > 2:
        print("usage: cluster-clones.py [--root <dir>] < report.json", file=sys.stderr)
        return 2
    if argv:
        root = argv[1]
    try:
        document = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError) as exc:
        print(
            f"cluster-clones.py: stdin is not a JSON document ({exc})", file=sys.stderr
        )
        return 2
    if not isinstance(document, dict):
        print("cluster-clones.py: stdin is not a JSON object", file=sys.stderr)
        return 2
    measures = document.get("measures")
    if isinstance(measures, list):
        document["measures"] = cluster(measures, root)
    print(json.dumps(document, indent=2))
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print(
            "cluster-clones.py needs Python %d.%d or later" % MIN_PYTHON,
            file=sys.stderr,
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
