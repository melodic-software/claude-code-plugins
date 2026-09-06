#!/usr/bin/env python3
"""Parse a coverage.py JSON report into the plugin's parser shape.

    parse(path) -> {file: {"lines": {line: hits}, "functions": [...] | None}}

Command line: `python3 coverage_py_json.py <artifact>` prints that mapping as
JSON. The module is named for the format rather than the tool, because a file
called `coverage.py` on `sys.path` would shadow the real package.

The report is what `coverage json` writes (`meta`, `files`, `totals`). Per
file it carries `executed_lines` and `missing_lines`, and, since coverage.py
7.6.0 (2024-07-11, "The JSON report now includes per-function and per-class
coverage information"), a `functions` mapping keyed by qualified name with the
same executed/missing shape per region. Those regions are exact, so a function
that has one joins as `artifact-region`; a report from an older coverage.py
has no `functions` key and the join falls back to the line range its
complexity collector reported.

Line hits are 1 or 0 here: the JSON report records which lines ran, not how
often, so a hit count is never invented beyond that.

The SQLite data file coverage.py writes while measuring is never read. Its
schema is documented by coverage.py itself as internal and free to change
without a major version bump, so the JSON report (or `coverage lcov`) is the
only supported route.

JSON carries no comment syntax, so `../fixtures/coverage/coverage-py.json`
cannot label itself: it is hand-written to this shape and is unverified
against a live run, a stamp `../../reference/collectors/audit-coverage.md`
records.
"""

from __future__ import annotations

import json
import sys
from typing import Any

MIN_PYTHON = (3, 9)
FORMAT = "coverage_py_json"


def _norm(path: str) -> str:
    path = str(path).strip().replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return path


def _lines(region: dict[str, Any]) -> dict[int, int]:
    out: dict[int, int] = {}
    for line in region.get("missing_lines") or []:
        if isinstance(line, int):
            out[line] = 0
    for line in region.get("executed_lines") or []:
        if isinstance(line, int):
            out[line] = 1
    return out


def parse(path: str) -> dict[str, dict]:
    """Read `path` and return the per-file coverage mapping."""
    with open(path, encoding="utf-8") as handle:
        document = json.load(handle)
    if not isinstance(document, dict) or not isinstance(document.get("files"), dict):
        raise ValueError("not a coverage.py JSON report (no `files` mapping)")
    files: dict[str, dict] = {}
    for name, entry in document["files"].items():
        if not isinstance(entry, dict):
            continue
        section: dict[str, Any] = {"lines": _lines(entry), "functions": None}
        regions = entry.get("functions")
        if isinstance(regions, dict):
            functions = []
            for function_name, region in regions.items():
                if not isinstance(region, dict):
                    continue
                region_lines = _lines(region)
                functions.append(
                    {
                        "name": function_name,
                        "start_line": min(region_lines) if region_lines else None,
                        "end_line": max(region_lines) if region_lines else None,
                        "hit": int(any(region_lines.values()))
                        if region_lines
                        else None,
                        "lines": region_lines or None,
                    }
                )
            functions.sort(
                key=lambda f: (f["start_line"] is None, f["start_line"] or 0)
            )
            section["functions"] = functions
        files[_norm(name)] = section
    return files


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: coverage_py_json.py <artifact>", file=sys.stderr)
        return 2
    print(json.dumps(parse(argv[0]), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print(
            "coverage_py_json.py needs Python %d.%d or later" % MIN_PYTHON,
            file=sys.stderr,
        )
        sys.exit(2)
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"coverage_py_json.py: {exc}", file=sys.stderr)
        sys.exit(2)
