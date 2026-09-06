#!/usr/bin/env python3
"""Adapter for `scc` (boyter/scc), used for comment-aware line counting only.

Adapter contract (design/contracts.md section 3): `probe`, `measures`,
`collect <lane> <measure> <file>...`, `install_hint`.

scc's `Complexity` figure is a per-file substring count and is never surfaced
by this plugin (Brief: "scc is not a cyclomatic collector"). Only the line
counts are read: Lines, Code, Comment, Blank, per file, from
`scc --by-file --format json`, whose top level is a list of per-language
objects each carrying `Files[]` with a `Location` (probed 2026-09-05 against
scc 3.7.0; the capture in fixtures/tool-output/scc.json is the reference
shape).
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

MIN_PYTHON = (3, 9)
NAME = "scc"


def _normalize(path: str) -> str:
    path = path.replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return os.path.normpath(path).replace("\\", "/")


def probe() -> int:
    exe = shutil.which("scc")
    if not exe:
        print("scc not on PATH", file=sys.stderr)
        return 1
    try:
        out = subprocess.run(
            [exe, "--version"], capture_output=True, text=True, check=False
        )
    except OSError as exc:
        print(f"scc --version failed: {exc}", file=sys.stderr)
        return 1
    match = re.search(r"(\d+\.\d+(?:\.\d+)?)", out.stdout + out.stderr)
    print(match.group(1) if match else "unknown-version")
    return 0


def translate(raw: str, lane: str, wanted: list[str]) -> list[dict]:
    wanted_norm = {_normalize(p): p for p in wanted}
    rows: list[dict] = []
    for language in json.loads(raw):
        for entry in language.get("Files", []):
            location = _normalize(entry.get("Location", ""))
            if location not in wanted_norm:
                continue
            lines = int(entry.get("Lines", 0))
            blank = int(entry.get("Blank", 0))
            rows.append(
                {
                    "file": wanted_norm[location].replace("\\", "/"),
                    "function": None,
                    "lane": lane,
                    "values": {
                        "lines_total": lines,
                        "lines_blank": blank,
                        "lines_comment": int(entry.get("Comment", 0)),
                        "lines_code": int(entry.get("Code", 0)),
                        "lines_non_blank": lines - blank,
                    },
                    "collector": NAME,
                    "labels": [],
                }
            )
    return rows


def collect(lane: str, measure: str, files: list[str]) -> int:
    if measure != "file_lines":
        print(f"scc.py: cannot collect {measure}", file=sys.stderr)
        return 2
    exe = shutil.which("scc")
    if not exe:
        print("scc not on PATH", file=sys.stderr)
        return 3
    result = subprocess.run(
        [exe, "--by-file", "--format", "json", *files],
        capture_output=True,
        text=True,
        check=False,
    )
    try:
        rows = translate(result.stdout, lane, files)
    except (json.JSONDecodeError, ValueError, TypeError) as exc:
        print(
            f"scc.py: unparsable scc output ({exc}); stderr: {result.stderr.strip()}",
            file=sys.stderr,
        )
        return 3
    for row in rows:
        print(json.dumps(row))
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        print(
            "usage: scc.py probe|measures|collect <lane> <measure> <file>...|install_hint",
            file=sys.stderr,
        )
        return 2
    verb, rest = argv[0], argv[1:]
    if verb == "probe":
        return probe()
    if verb == "measures":
        print("*/file_lines")
        return 0
    if verb == "install_hint":
        print(
            "scc: https://github.com/boyter/scc (go install github.com/boyter/scc/v3@latest, brew install scc, or a release binary)"
        )
        return 0
    if verb == "collect":
        if len(rest) < 2:
            print("usage: scc.py collect <lane> <measure> <file>...", file=sys.stderr)
            return 2
        return collect(rest[0], rest[1], rest[2:])
    print(f"scc.py: unknown verb {verb}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print("scc.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
