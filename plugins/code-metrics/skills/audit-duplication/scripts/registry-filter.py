#!/usr/bin/env python3
"""Drop the clone groups a sanctioned-replication registry accounts for.

    registry-filter.py --root <dir> [--registry <file>]... [--zero-floor] [< report.json]

Reads a `code-metrics/v1` document on stdin and prints it back with every
clone group the registries sanction moved out of `measures[]` and into
`excluded[]`. Design thread T8: deliberate replication a repository declares
about itself is an EXCLUSION derived from that declaration, not a suppression
of a finding, so no suppression record is involved and the excluded groups stay
visible in the document.

A registry is a text file with one path-within-plugin per line, `#` comments
and blank lines ignored (this repository's own
`scripts/cross-plugin-source-registry.txt` is the shape). A clone group is
dropped when one registry line accounts for EVERY instance: each instance's
path, relative to `--root` and written with forward slashes, is that line or
ends with `/` plus that line, and the prefixes in front of that suffix are all
distinct, so the copies sit in different carrying directories. Two clones
inside one directory are ordinary duplication and stay.

Each dropped group is appended to `excluded[]` as `{"registry", "line",
"path", "instances"}`, naming the registry file, the 1-based line number, and
the line's text that sanctioned it. Rows without `instances` pass through
untouched, and `summary` is left alone: the caller recomputes it with
`report.py resummarize`.

`--zero-floor` is the pass the caller runs AFTER that recomputation, with no
registries: it states `duplicated_lines: 0` and `clone_groups: 0` when a
duplication collector ran and every group it found was excluded, because the
summary is derived from the surviving rows and would otherwise carry neither
key. A run that measured nothing gets no floor.

Exit 0 when the document was printed, 2 on a usage error, which includes a
registry file that does not exist and a stdin document that is not JSON.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any

MIN_PYTHON = (3, 9)


def read_registry(path: str) -> list[tuple[int, str]]:
    entries: list[tuple[int, str]] = []
    with open(path, encoding="utf-8") as handle:
        for number, raw in enumerate(handle, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            entries.append((number, line.replace("\\", "/").lstrip("/")))
    return entries


def relative(path: str, root: str) -> str:
    path = (path or "").replace("\\", "/")
    if os.path.isabs(path) and root:
        try:
            path = os.path.relpath(path, root).replace("\\", "/")
        except ValueError:
            return path
    while path.startswith("./"):
        path = path[2:]
    return path


def sanctions(entry: str, instances: list[dict[str, Any]], root: str) -> bool:
    """True when this registry line accounts for every instance of the group."""
    if len(instances) < 2:
        return False
    prefixes = set()
    for instance in instances:
        path = relative(str(instance.get("file", "")), root)
        if path == entry:
            prefix = ""
        elif path.endswith("/" + entry):
            prefix = path[: -(len(entry) + 1)]
        else:
            return False
        if prefix in prefixes:
            return False
        prefixes.add(prefix)
    return True


def filter_document(
    document: dict[str, Any],
    registries: list[tuple[str, list[tuple[int, str]]]],
    root: str,
) -> dict[str, Any]:
    kept: list[dict[str, Any]] = []
    excluded: list[dict[str, Any]] = list(document.get("excluded") or [])
    for row in document.get("measures") or []:
        instances = row.get("instances")
        match = None
        if instances:
            for registry_path, entries in registries:
                for number, entry in entries:
                    if sanctions(entry, instances, root):
                        match = (registry_path, number, entry)
                        break
                if match:
                    break
        if match:
            excluded.append(
                {
                    "registry": match[0].replace("\\", "/"),
                    "line": match[1],
                    "path": match[2],
                    "instances": instances,
                }
            )
        else:
            kept.append(row)
    document["measures"] = kept
    document["excluded"] = excluded
    return document


def floor_summary(document: dict[str, Any]) -> dict[str, Any]:
    """State a zero the summary would otherwise omit.

    `report.py summarize` derives `duplicated_lines` and `clone_groups` from
    the surviving clone-group rows, so a run whose every group was excluded
    carries neither key. Zero measured duplication is a measurement and is
    printed as one, but only when a duplication collector actually ran: a run
    that measured nothing keeps its "Measured nothing" headline instead of an
    unearned zero.
    """
    measured = any(
        row.get("measure") == "duplication" and row.get("status") == "ok"
        for row in document.get("run") or []
    )
    if measured:
        summary = document.setdefault("summary", {})
        summary.setdefault("duplicated_lines", 0)
        summary.setdefault("clone_groups", 0)
    return document


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="registry-filter.py", add_help=True)
    parser.add_argument("--root", default="")
    parser.add_argument("--registry", action="append", default=[])
    parser.add_argument("--zero-floor", action="store_true")
    args = parser.parse_args(argv)

    registries: list[tuple[str, list[tuple[int, str]]]] = []
    for path in args.registry:
        if not os.path.isfile(path):
            print(f"registry-filter.py: registry not found: {path}", file=sys.stderr)
            return 2
        registries.append((path, read_registry(path)))
    try:
        document = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError) as exc:
        print(
            f"registry-filter.py: stdin is not a JSON document ({exc})", file=sys.stderr
        )
        return 2
    document = filter_document(document, registries, args.root)
    if args.zero_floor:
        document = floor_summary(document)
    print(json.dumps(document, indent=2))
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print(
            "registry-filter.py needs Python %d.%d or later" % MIN_PYTHON,
            file=sys.stderr,
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
