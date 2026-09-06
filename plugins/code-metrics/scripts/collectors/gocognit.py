#!/usr/bin/env python3
"""Adapter for `gocognit` (uudashr/gocognit), cognitive complexity for Go.

Adapter contract (design/contracts.md section 3): `probe`, `measures`,
`collect <lane> <measure> <file>...`, `install_hint`.

`gocognit -json -over 0 <files>` prints a list of

    {"PkgName", "FuncName", "Complexity", "Pos": {"Filename", "Line", ...}}

with no end line (probed 2026-09-05 against gocognit v1.2.1; the capture in
fixtures/tool-output/gocognit.json is the reference shape). Rows carry
`end_line: null` and the label `start-line-only` (design T7).

Go is the only lane with a maintained cognitive-complexity collector besides
TypeScript's `eslint-plugin-sonarjs`; Python and Bash report the gap instead
(design T11). The measure is Campbell's (SonarSource) and no standard sets a
threshold for it.

v1.2.1 understands no version flag, so `probe` tries `-version` and then
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
NAME = "gocognit"
LANE = "go"
MEASURE = "cognitive"
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
    wanted_norm = {_normalize(p): p for p in wanted}
    document = json.loads(raw)
    if not isinstance(document, list):
        raise ValueError("gocognit -json did not print an array")
    rows: list[dict] = []
    for entry in document:
        if not isinstance(entry, dict):
            continue
        position = entry.get("Pos") or {}
        path = wanted_norm.get(_normalize(position.get("Filename", "")))
        if path is None:
            continue
        rows.append(
            {
                "file": path.replace("\\", "/"),
                "function": entry.get("FuncName"),
                "start_line": position.get("Line"),
                "end_line": None,
                "lane": lane,
                "values": {MEASURE: entry.get("Complexity")},
                "collector": NAME,
                "labels": ["start-line-only"],
            }
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
        [exe, "-json", "-over", "0", *files],
        capture_output=True,
        text=True,
        check=False,
    )
    try:
        rows = translate(result.stdout, lane, files)
    except (json.JSONDecodeError, ValueError, TypeError, AttributeError) as exc:
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
            "gocognit: https://github.com/uudashr/gocognit (go install github.com/uudashr/gocognit/cmd/gocognit@latest)"
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
        print("gocognit.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
