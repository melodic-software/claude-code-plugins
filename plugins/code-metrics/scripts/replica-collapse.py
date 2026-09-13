#!/usr/bin/env python3
"""Collapse the rows a sanctioned-replication registry accounts for.

    replica-collapse.py [--prefix <git show-prefix>] [--registry <file>]... [< report.json]

Reads a `code-metrics/v1` document on stdin and prints it back with every set
of per-file or per-function rows that a registry line sanctions collapsed
into one row. A repository that vendors one file into several plugins
measures that file's functions once per copy, and every copy over a reference
is counted again, so the copies bury the rows that are not copies. The
registry is the repository's own declaration that those copies are deliberate
(the same file `registry-filter.py` reads for clone groups), so the report
shows the function once and says how many files the row stands for.

A registry is a text file with one path-within-plugin per line, `#` comments
and blank lines ignored. A row belongs to a registry line when its `file`,
made root-relative through `--prefix` (the `git rev-parse --show-prefix` of
the directory the audit ran from) and written with forward slashes, is that
line or ends with `/` plus that line. Rows collapse together when they share
the registry line, the function name, the start and end line, the collector,
the lane, and every measured value, and sit under distinct carrying prefixes;
two rows whose numbers differ are two different files whatever the registry
says, and both stay. Clone-group rows (`instances[]`) are never touched; they
belong to `registry-filter.py`.

The surviving row is the first by path. It gains the label `replicated` and a
`replicas` object: `count` (files the row stands for, the survivor included),
`registry`, `line`, `path` (the registry line's text), and `files` (every
path collapsed into it). `summary` is left alone: the caller recomputes it
with `report.py resummarize`.

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
LABEL = "replicated"


def read_registry(path: str) -> list[tuple[int, str]]:
    entries: list[tuple[int, str]] = []
    with open(path, encoding="utf-8") as handle:
        for number, raw in enumerate(handle, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            # A cluster line (`<canonical> -> <member>...`) names a root
            # canonical outside any plugin and the globs that carry it; it is
            # the clone-group reader's (registry-filter.py) and never a
            # path-within-plugin, so this pass leaves it alone.
            if " -> " in line:
                continue
            entries.append((number, line.replace("\\", "/").lstrip("/")))
    return entries


def root_relative(path: str, prefix: str) -> str:
    """The path as the repository root sees it, collapsed lexically.

    The scope is cwd-relative and a registry line is root-relative, so the
    directory the audit ran from is put back in front. Segments are collapsed
    in text rather than through the filesystem, so a scoped path need not
    exist and a symlink cannot move a file out of the directory a registry
    line names.
    """
    text = (prefix or "").replace("\\", "/") + (path or "").replace("\\", "/")
    kept: list[str] = []
    for segment in text.split("/"):
        if segment in ("", "."):
            continue
        if segment == ".." and kept and kept[-1] != "..":
            kept.pop()
            continue
        kept.append(segment)
    return "/".join(kept)


def carrier(rootrel: str, entry: str) -> str | None:
    """The prefix in front of a registry line, or None when it is not this line."""
    if rootrel == entry:
        return ""
    if rootrel.endswith("/" + entry):
        return rootrel[: -(len(entry) + 1)]
    return None


def collapse(
    document: dict[str, Any],
    registries: list[tuple[str, list[tuple[int, str]]]],
    prefix: str,
) -> dict[str, Any]:
    groups: dict[tuple[Any, ...], list[tuple[str, dict[str, Any]]]] = {}
    order: list[tuple[Any, ...]] = []
    passthrough: list[tuple[int, dict[str, Any]]] = []
    first_index: dict[tuple[Any, ...], int] = {}
    for index, row in enumerate(document.get("measures") or []):
        match = None
        if not row.get("instances") and row.get("file"):
            rootrel = root_relative(str(row["file"]), prefix)
            for registry_path, entries in registries:
                for number, entry in entries:
                    where = carrier(rootrel, entry)
                    if where is not None:
                        match = (registry_path, number, entry, where)
                        break
                if match:
                    break
        if not match:
            passthrough.append((index, row))
            continue
        registry_path, number, entry, where = match
        key = (
            registry_path,
            number,
            entry,
            row.get("function"),
            row.get("start_line"),
            row.get("end_line"),
            row.get("collector"),
            row.get("lane"),
            json.dumps(row.get("values") or {}, sort_keys=True),
        )
        if key not in groups:
            groups[key] = []
            order.append(key)
            first_index[key] = index
        groups[key].append((where, row))

    merged: list[tuple[int, dict[str, Any]]] = []
    for key in order:
        members = groups[key]
        prefixes = {where for where, _ in members}
        if len(members) < 2 or len(prefixes) != len(members):
            merged.extend((first_index[key], row) for _, row in members)
            continue
        members.sort(key=lambda item: str(item[1].get("file")))
        survivor = dict(members[0][1])
        labels = list(survivor.get("labels") or [])
        if LABEL not in labels:
            labels.append(LABEL)
        survivor["labels"] = labels
        survivor["replicas"] = {
            "count": len(members),
            "registry": key[0].replace("\\", "/"),
            "line": key[1],
            "path": key[2],
            "files": [str(row.get("file")) for _, row in members],
        }
        merged.append((first_index[key], survivor))

    rows = sorted(passthrough + merged, key=lambda item: item[0])
    document["measures"] = [row for _, row in rows]
    return document


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="replica-collapse.py", add_help=True)
    parser.add_argument("--prefix", default="")
    parser.add_argument("--registry", action="append", default=[])
    args = parser.parse_args(argv)

    registries: list[tuple[str, list[tuple[int, str]]]] = []
    for path in args.registry:
        if not os.path.isfile(path):
            print(f"replica-collapse.py: registry not found: {path}", file=sys.stderr)
            return 2
        registries.append((path, read_registry(path)))
    try:
        document = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError) as exc:
        print(
            f"replica-collapse.py: stdin is not a JSON document ({exc})",
            file=sys.stderr,
        )
        return 2
    print(json.dumps(collapse(document, registries, args.prefix), indent=2))
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print(
            "replica-collapse.py needs Python %d.%d or later" % MIN_PYTHON,
            file=sys.stderr,
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
