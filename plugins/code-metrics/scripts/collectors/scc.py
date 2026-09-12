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

from adapter_paths import files_from

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


# Argument-vector budget for one scc invocation, in characters. Git Bash under
# Windows caps a native process's command line near 32,000 characters, so a
# lane of thousands of paths is fed to scc in chunks that stay under it.
# CODE_METRICS_ARGV_BUDGET overrides the figure (the suite uses it to force
# several chunks over a small fixture).
ARGV_BUDGET = 24000


def _chunks(files: list[str]) -> list[list[str]]:
    budget = ARGV_BUDGET
    override = os.environ.get("CODE_METRICS_ARGV_BUDGET")
    if override and override.isdigit() and int(override) > 0:
        budget = int(override)
    chunks: list[list[str]] = []
    current: list[str] = []
    used = 0
    for path in files:
        cost = len(path) + 1
        if current and used + cost > budget:
            chunks.append(current)
            current, used = [], 0
        current.append(path)
        used += cost
    if current:
        chunks.append(current)
    return chunks


def _count_lines(path: str) -> dict[str, int | None]:
    """The bundled counter's figures for a file scc produced no row for.

    scc lists only the files whose language it recognises, so a lockfile or
    an extensionless text file in the catch-all lane comes back with no
    `Files[]` entry; dropping it would report the lane as measured with the
    file missing. Its total and blank lines are counted here, comment-agnostic
    like the bundled counter, and the row says so through its label."""
    total = blank = 0
    with open(path, "rb") as handle:
        for raw in handle:
            total += 1
            if not raw.strip():
                blank += 1
    return {
        "lines_total": total,
        "lines_blank": blank,
        "lines_comment": None,
        "lines_code": None,
        "lines_non_blank": total - blank,
    }


def translate(raw: str, lane: str, wanted: list[str]) -> list[dict]:
    """Rows for `wanted`, in scc's output order, from one scc document."""
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


def fill_missing(rows: list[dict], lane: str, wanted: list[str]) -> list[dict]:
    """Append a comment-agnostic row for every requested file scc omitted, so
    the lane never reads as measured while a file in it was not."""
    seen = {_normalize(row["file"]) for row in rows}
    filled = list(rows)
    for path in wanted:
        if _normalize(path) in seen:
            continue
        seen.add(_normalize(path))
        filled.append(
            {
                "file": path.replace("\\", "/"),
                "function": None,
                "lane": lane,
                "values": _count_lines(path),
                "collector": NAME,
                "labels": ["comment-agnostic"],
            }
        )
    return filled


def collect(lane: str, measure: str, files: list[str]) -> int:
    if measure != "file_lines":
        print(f"scc.py: cannot collect {measure}", file=sys.stderr)
        return 2
    exe = shutil.which("scc")
    if not exe:
        print("scc not on PATH", file=sys.stderr)
        return 3
    rows: list[dict] = []
    for chunk in _chunks(files):
        result = subprocess.run(
            [exe, "--by-file", "--format", "json", *chunk],
            capture_output=True,
            text=True,
            check=False,
        )
        try:
            rows.extend(translate(result.stdout, lane, chunk))
        except (json.JSONDecodeError, ValueError, TypeError) as exc:
            print(
                f"scc.py: unparsable scc output ({exc}); stderr: {result.stderr.strip()}",
                file=sys.stderr,
            )
            return 3
    try:
        rows = fill_missing(rows, lane, files)
    except OSError as exc:
        print(f"scc.py: {exc}", file=sys.stderr)
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
        return collect(rest[0], rest[1], files_from(rest[2:]))
    print(f"scc.py: unknown verb {verb}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print("scc.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
