#!/usr/bin/env python3
"""Adapter for `lizard` (terryyin/lizard), per-function cyclomatic complexity.

Adapter contract (design/contracts.md section 3): `probe`, `measures`,
`collect <lane> <measure> <file>...`, `install_hint`.

`lizard --csv <files>` prints one record per function with no header, in the
column order `NLOC, CCN, token, PARAM, length, "name@start-end@file", file,
name, long_name, start, end` (probed 2026-09-05 against lizard 1.24.0; the
capture in fixtures/tool-output/lizard.csv is the reference shape). Start and
end lines are both present, which is what lets the CRAP join in
`audit-coverage` bound a function's lines.

Two measures are served for the TypeScript, Python, and Go lanes:

  cyclomatic       values {"cyclomatic": CCN}
  function_lines   values {"function_lines", "function_lines_pct"}, the
                   ISO/IEC 5055:2021 section 8.2.115 form: the function's
                   non-empty lines, and those as a percentage of the file's
                   non-empty lines. The line counts are read from the source
                   file, because lizard's NLOC excludes comments.

lizard does not parse shell, so there is no bash rung.
"""

from __future__ import annotations

import csv
import io
import json
import os
import re
import shutil
import subprocess
import sys

MIN_PYTHON = (3, 9)
NAME = "lizard"
LANES = ("typescript", "python", "go")
MEASURES = ("cyclomatic", "function_lines")


def _normalize(path: str) -> str:
    path = path.replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return os.path.normpath(path).replace("\\", "/")


def probe() -> int:
    exe = shutil.which(NAME)
    if not exe:
        print(f"{NAME} not on PATH", file=sys.stderr)
        return 1
    try:
        out = subprocess.run(
            [exe, "--version"], capture_output=True, text=True, check=False
        )
    except OSError as exc:
        print(f"{NAME} --version failed: {exc}", file=sys.stderr)
        return 1
    match = re.search(r"(\d+\.\d+(?:\.\d+)?)", out.stdout + out.stderr)
    print(match.group(1) if match else "unknown-version")
    return 0


def _source_lines(path: str, cache: dict[str, list[str]]) -> list[str]:
    if path not in cache:
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                cache[path] = handle.read().splitlines()
        except OSError:
            cache[path] = []
    return cache[path]


def translate(raw: str, lane: str, measure: str, wanted: list[str]) -> list[dict]:
    """Rows for the requested files. Raises ValueError when no record parsed."""
    wanted_norm = {_normalize(p): p for p in wanted}
    cache: dict[str, list[str]] = {}
    rows: list[dict] = []
    parsed = 0
    for record in csv.reader(io.StringIO(raw)):
        if len(record) < 11:
            continue
        try:
            ccn, start, end = int(record[1]), int(record[9]), int(record[10])
        except ValueError:
            continue
        parsed += 1
        location = _normalize(record[6])
        if location not in wanted_norm:
            continue
        path = wanted_norm[location]
        if measure == "cyclomatic":
            values: dict = {"cyclomatic": ccn}
        else:
            lines = _source_lines(path, cache)
            total = sum(1 for line in lines if line.strip())
            inside = sum(1 for line in lines[start - 1 : end] if line.strip())
            values = {
                "function_lines": inside,
                "function_lines_pct": round(100.0 * inside / total, 2)
                if total
                else None,
            }
        rows.append(
            {
                "file": path.replace("\\", "/"),
                "function": record[7],
                "start_line": start,
                "end_line": end,
                "lane": lane,
                "values": values,
                "collector": NAME,
                "labels": [],
            }
        )
    if not parsed:
        raise ValueError("no CSV record with the eleven lizard columns")
    return rows


def collect(lane: str, measure: str, files: list[str]) -> int:
    if lane not in LANES or measure not in MEASURES:
        print(f"{NAME}.py: cannot collect {lane}/{measure}", file=sys.stderr)
        return 2
    exe = shutil.which(NAME)
    if not exe:
        print(f"{NAME} not on PATH", file=sys.stderr)
        return 3
    result = subprocess.run(
        [exe, "--csv", *files], capture_output=True, text=True, check=False
    )
    try:
        rows = translate(result.stdout, lane, measure, files)
    except ValueError as exc:
        print(
            f"{NAME}.py: no parseable {NAME} output ({exc}); "
            f"stderr: {result.stderr.strip()}",
            file=sys.stderr,
        )
        return 3
    for row in rows:
        print(json.dumps(row))
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        print(
            f"usage: {NAME}.py probe|measures|collect <lane> <measure> <file>...|install_hint",
            file=sys.stderr,
        )
        return 2
    verb, rest = argv[0], argv[1:]
    if verb == "probe":
        return probe()
    if verb == "measures":
        for lane in LANES:
            for measure in MEASURES:
                print(f"{lane}/{measure}")
        return 0
    if verb == "install_hint":
        print(
            "lizard: https://github.com/terryyin/lizard (pip install lizard, or pipx install lizard)"
        )
        return 0
    if verb == "collect":
        if len(rest) < 3:
            print(
                f"usage: {NAME}.py collect <lane> <measure> <file>...", file=sys.stderr
            )
            return 2
        return collect(rest[0], rest[1], rest[2:])
    print(f"{NAME}.py: unknown verb {verb}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print("lizard.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
