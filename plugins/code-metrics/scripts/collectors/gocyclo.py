#!/usr/bin/env python3
"""Adapter for `gocyclo` (fzipp/gocyclo), the Go lane's native collector.

Adapter contract (design/contracts.md section 3): `probe`, `measures`,
`collect <lane> <measure> <file>...`, `install_hint`.

`gocyclo -over 0 <files>` prints one line per function,

    <ccn> <package> <function> <file>:<line>:<column>

with no end line (probed 2026-09-05 against gocyclo v0.6.0; the capture in
fixtures/tool-output/gocyclo.txt is the reference shape). Rows therefore
carry `end_line: null` and the label `start-line-only`, which is what makes
`audit-coverage` report `go/crap: not-applicable` when this rung is the one
that resolved rather than `lizard` (design T7).

v0.6.0 understands no version flag, so `probe` tries `-version` and then
`--version`, prints `unknown-version` when neither answers, and still exits 0
because the tool itself resolved.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys

from adapter_paths import (
    UNKNOWN_VERSION,
    dispatch,
    normalize,
    require_python,
    version_in,
    version_output,
)

NAME = "gocyclo"
LANE = "go"
MEASURE = "cyclomatic"


def probe() -> int:
    exe = shutil.which(NAME)
    if not exe:
        print(f"{NAME} not on PATH", file=sys.stderr)
        return 1
    for flag in ("-version", "--version"):
        output = version_output(exe, NAME, flag)
        if output is None:
            return 1
        found = version_in(output)
        if found is not None:
            print(found)
            return 0
    print(UNKNOWN_VERSION)
    return 0


def translate(raw: str, lane: str, wanted: list[str]) -> list[dict]:
    """Rows for the requested files. Raises ValueError when no line parsed."""
    wanted_norm = {normalize(p): p for p in wanted}
    rows: list[dict] = []
    parsed = 0
    for line in raw.splitlines():
        fields = line.split()
        if len(fields) < 4:
            continue
        location = fields[-1].rsplit(":", 2)
        if len(location) != 3:
            continue
        try:
            complexity, start = int(fields[0]), int(location[1])
        except ValueError:
            continue
        parsed += 1
        path = wanted_norm.get(normalize(location[0]))
        if path is None:
            continue
        rows.append(
            {
                "file": path.replace("\\", "/"),
                "function": " ".join(fields[2:-1]),
                "start_line": start,
                "end_line": None,
                "lane": lane,
                "values": {MEASURE: complexity},
                "collector": NAME,
                "labels": ["start-line-only"],
            }
        )
    if not parsed:
        raise ValueError(
            "no line in the '<ccn> <package> <function> <file>:<line>:<column>' form"
        )
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
        [exe, "-over", "0", *files], capture_output=True, text=True, check=False
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


INSTALL_HINT = "gocyclo: https://github.com/fzipp/gocyclo (go install github.com/fzipp/gocyclo/cmd/gocyclo@latest)"


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
