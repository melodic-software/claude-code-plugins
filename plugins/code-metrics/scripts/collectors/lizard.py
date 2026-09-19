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

NAME = "lizard"
LANES = ("typescript", "python", "go")
MEASURES = ("cyclomatic", "function_lines")


def probe() -> int:
    exe = shutil.which(NAME)
    if not exe:
        print(f"{NAME} not on PATH", file=sys.stderr)
        return 1
    output = version_output(exe, NAME)
    if output is None:
        return 1
    print(version_or_unknown(output))
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
    wanted_norm = {normalize(p): p for p in wanted}
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
        path = wanted_norm.get(normalize(record[6]))
        if path is None:
            continue
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


def measures() -> None:
    for lane in LANES:
        for measure in MEASURES:
            print(f"{lane}/{measure}")


INSTALL_HINT = "lizard: https://github.com/terryyin/lizard (pip install lizard, or pipx install lizard)"


def main(argv: list[str]) -> int:
    return dispatch(
        NAME,
        argv,
        probe=probe,
        measures=measures,
        install_hint=INSTALL_HINT,
        collect=collect,
        collect_min=3,
    )


if __name__ == "__main__":
    require_python(f"{NAME}.py")
    sys.exit(main(sys.argv[1:]))
