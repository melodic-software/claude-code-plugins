#!/usr/bin/env python3
"""Adapter for `multimetric` (priv-kweihmann/multimetric), the Halstead rung.

Adapter contract (design/contracts.md section 3): `probe`, `measures`,
`collect <lane> <measure> <file>...`, `install_hint`.

`multimetric <files>` prints one JSON document whose `files` object is keyed
by absolute path (probed 2026-09-05 against multimetric 2.4.4; the capture in
fixtures/tool-output/multimetric.json is the reference shape, with the
machine-specific prefix of its keys replaced by a portable one). Keys are
mapped back to the paths the dispatcher passed by path-segment suffix.

The numbers are per file, not per function, so every row carries
`function: null`, `start_line: null`, `end_line: null` and the label
`file-level` (design T12: multimetric has no per-function granularity, and it
is the only cross-lane Halstead route the tooling corpus found).

It also serves `bash/cyclomatic` as the fallback below `shellmetrics`, with
the label `multimetric-approximation`: its count under-reports against a
per-function parser (its Python cyclomatic read 1 where radon read 3 for the
same function), so the figure is never used where `lizard` or `radon`
resolves.

multimetric understands no version flag, so `probe` prints
`unknown-version` when its usage text carries no version and still exits 0,
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
NAME = "multimetric"
HALSTEAD_LANES = ("typescript", "python", "bash", "go")
CYCLOMATIC_LANES = ("bash",)


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


def match_path(location: str, wanted_norm: dict[str, str]) -> str | None:
    """multimetric keys its files by absolute path; map one back to the path
    the dispatcher passed, by exact match first and then by segment suffix."""
    norm = _normalize(location)
    if norm in wanted_norm:
        return wanted_norm[norm]
    for key, original in wanted_norm.items():
        if norm.endswith("/" + key):
            return original
    return None


def translate(raw: str, lane: str, measure: str, wanted: list[str]) -> list[dict]:
    wanted_norm = {_normalize(p): p for p in wanted}
    document = json.loads(raw)
    if not isinstance(document, dict) or not isinstance(document.get("files"), dict):
        raise ValueError("multimetric did not print a document with a `files` object")
    rows: list[dict] = []
    for location, metrics in document["files"].items():
        path = match_path(location, wanted_norm)
        if path is None or not isinstance(metrics, dict):
            continue
        if measure == "halstead":
            values: dict = {
                "halstead_difficulty": metrics.get("halstead_difficulty"),
                "halstead_volume": metrics.get("halstead_volume"),
                "halstead_effort": metrics.get("halstead_effort"),
            }
            labels = ["file-level"]
        else:
            values = {"cyclomatic": metrics.get("cyclomatic_complexity")}
            labels = ["multimetric-approximation"]
        rows.append(
            {
                "file": path.replace("\\", "/"),
                "function": None,
                "start_line": None,
                "end_line": None,
                "lane": lane,
                "values": values,
                "collector": NAME,
                "labels": labels,
            }
        )
    return rows


def collect(lane: str, measure: str, files: list[str]) -> int:
    served = (measure == "halstead" and lane in HALSTEAD_LANES) or (
        measure == "cyclomatic" and lane in CYCLOMATIC_LANES
    )
    if not served:
        print(f"{NAME}.py: cannot collect {lane}/{measure}", file=sys.stderr)
        return 2
    exe = shutil.which(NAME)
    if not exe:
        print(f"{NAME} not on PATH", file=sys.stderr)
        return 3
    result = subprocess.run([exe, *files], capture_output=True, text=True, check=False)
    try:
        rows = translate(result.stdout, lane, measure, files)
    except (json.JSONDecodeError, ValueError, TypeError) as exc:
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
        for lane in HALSTEAD_LANES:
            print(f"{lane}/halstead")
        for lane in CYCLOMATIC_LANES:
            print(f"{lane}/cyclomatic")
        return 0
    if verb == "install_hint":
        print(
            "multimetric: https://github.com/priv-kweihmann/multimetric (pip install multimetric)"
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
        print(
            "multimetric.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
