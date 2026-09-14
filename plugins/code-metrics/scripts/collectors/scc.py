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
import shutil
import subprocess
import sys

from adapter_paths import (
    dispatch,
    normalize,
    require_python,
    version_or_unknown,
    version_output,
)

NAME = "scc"


def probe() -> int:
    exe = shutil.which("scc")
    if not exe:
        print("scc not on PATH", file=sys.stderr)
        return 1
    output = version_output(exe, "scc")
    if output is None:
        return 1
    print(version_or_unknown(output))
    return 0


# Argument-vector budget for one scc invocation, in characters. Git Bash under
# Windows caps a native process's command line near 32,000 characters, so a
# lane of thousands of paths is fed to scc in chunks that stay under it.
# CODE_METRICS_ARGV_BUDGET overrides the figure (the suite uses it to force
# several chunks over a small fixture).
ARGV_BUDGET = 24000


def _chunks(files: list[str]) -> list[list[str]]:
    budget = ARGV_BUDGET
    override = os.environ.get("CODE_METRICS_ARGV_BUDGET", "")
    if override.isdigit() and int(override) > 0:
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


def _row(
    lane: str, path: str, values: dict[str, int | None], labels: list[str]
) -> dict:
    return {
        "file": path.replace("\\", "/"),
        "function": None,
        "lane": lane,
        "values": values,
        "collector": NAME,
        "labels": labels,
    }


def translate(raw: str, lane: str, wanted: list[str]) -> list[dict]:
    """Rows for `wanted`, in scc's output order, from one scc document."""
    wanted_norm = {normalize(p): p for p in wanted}
    rows: list[dict] = []
    for language in json.loads(raw):
        for entry in language.get("Files", []):
            location = normalize(entry.get("Location", ""))
            if location not in wanted_norm:
                continue
            lines = int(entry.get("Lines", 0))
            blank = int(entry.get("Blank", 0))
            rows.append(
                _row(
                    lane,
                    wanted_norm[location],
                    {
                        "lines_total": lines,
                        "lines_blank": blank,
                        "lines_comment": int(entry.get("Comment", 0)),
                        "lines_code": int(entry.get("Code", 0)),
                        "lines_non_blank": lines - blank,
                    },
                    [],
                )
            )
    return rows


def fill_missing(rows: list[dict], lane: str, wanted: list[str]) -> list[dict]:
    """Append a comment-agnostic row for every requested file scc omitted, so
    the lane never reads as measured while a file in it was not."""
    seen = {normalize(row["file"]) for row in rows}
    filled = list(rows)
    for path in wanted:
        key = normalize(path)
        if key in seen:
            continue
        seen.add(key)
        filled.append(_row(lane, path, _count_lines(path), ["comment-agnostic"]))
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
        except (ValueError, TypeError) as exc:
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


def measures() -> None:
    print("*/file_lines")


INSTALL_HINT = "scc: https://github.com/boyter/scc (go install github.com/boyter/scc/v3@latest, brew install scc, or a release binary)"


def main(argv: list[str]) -> int:
    return dispatch(
        NAME,
        argv,
        probe=probe,
        measures=measures,
        install_hint=INSTALL_HINT,
        collect=collect,
    )


if __name__ == "__main__":
    require_python(f"{NAME}.py")
    sys.exit(main(sys.argv[1:]))
