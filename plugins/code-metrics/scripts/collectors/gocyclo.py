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
import os
import re
import shutil
import subprocess
import sys

MIN_PYTHON = (3, 9)
NAME = "gocyclo"
LANE = "go"
MEASURE = "cyclomatic"
VERSION = re.compile(r"(\d+\.\d+(?:\.\d+)?)")


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
    for flag in ("-version", "--version"):
        try:
            out = subprocess.run(
                [exe, flag], capture_output=True, text=True, check=False
            )
        except OSError as exc:
            print(f"{NAME} {flag} failed: {exc}", file=sys.stderr)
            return 1
        match = VERSION.search(out.stdout + out.stderr)
        if match:
            print(match.group(1))
            return 0
    print("unknown-version")
    return 0


def translate(raw: str, lane: str, wanted: list[str]) -> list[dict]:
    """Rows for the requested files. Raises ValueError when no line parsed."""
    wanted_norm = {_normalize(p): p for p in wanted}
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
        path = wanted_norm.get(_normalize(location[0]))
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
        print(f"{LANE}/{MEASURE}")
        return 0
    if verb == "install_hint":
        print(
            "gocyclo: https://github.com/fzipp/gocyclo (go install github.com/fzipp/gocyclo/cmd/gocyclo@latest)"
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
        print("gocyclo.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
