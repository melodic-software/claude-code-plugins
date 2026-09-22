#!/usr/bin/env python3
"""Adapter for `shellmetrics` (shellspec/shellmetrics), the Bash lane.

Adapter contract (design/contracts.md section 3): `probe`, `measures`,
`collect <lane> <measure> <file>...`, `install_hint`.

`shellmetrics --csv <files>` prints a header and then one record per shell
function in the column order

    file, func, lineno, lloc, ccn, lines, comment, blank

plus the `<begin>`, `<main>` and `<end>` pseudo-records, which carry
file-level totals rather than a function and are dropped here. There is no
end line, so rows carry `end_line: null` and the label `start-line-only`,
which is why Bash has no CRAP in this version (design T7, and the ladder's
`bash function_lines none` rung).

`lizard` does not parse shell, so this is the Bash lane's first rung;
`multimetric` is the fallback and is labeled an approximation because it
under-counts (its Python cyclomatic read 1 where radon read 3 for the same
function, probed 2026-09-05).

The capture in fixtures/tool-output/shellmetrics.csv is written to that
documented format; the sandbox had no `shellmetrics`, so the file carries a
first-line comment marking it unverified, and comment lines are skipped here.
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

NAME = "shellmetrics"
LANE = "bash"
MEASURE = "cyclomatic"
PSEUDO = ("<begin>", "<main>", "<end>")


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


def translate(raw: str, lane: str, wanted: list[str]) -> list[dict]:
    """Rows for the requested files. Raises ValueError when no record parsed."""
    wanted_norm = {normalize(p): p for p in wanted}
    rows: list[dict] = []
    parsed = 0
    for record in csv.reader(io.StringIO(raw)):
        if len(record) < 5 or record[0].startswith("#") or record[0] == "file":
            continue
        try:
            start, complexity = int(record[2]), int(record[4])
        except ValueError:
            continue
        parsed += 1
        if record[1] in PSEUDO:
            continue
        # The pseudo-records append `|lines:comment:blank` to the file cell;
        # a function record does not, but splitting is harmless either way.
        path = wanted_norm.get(normalize(record[0].split("|", 1)[0]))
        if path is None:
            continue
        rows.append(
            {
                "file": path.replace("\\", "/"),
                "function": record[1],
                "start_line": start,
                "end_line": None,
                "lane": lane,
                "values": {MEASURE: complexity},
                "collector": NAME,
                "labels": ["start-line-only"],
            }
        )
    if not parsed:
        raise ValueError("no CSV record in the shellmetrics column order")
    return rows


def collect(lane: str, measure: str, files: list[str]) -> int:
    if lane != LANE or measure != MEASURE:
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
        rows = translate(result.stdout, lane, files)
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
    print(f"{LANE}/{MEASURE}")


INSTALL_HINT = "shellmetrics: https://github.com/shellspec/shellmetrics (one POSIX shell script; place it on PATH)"


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
