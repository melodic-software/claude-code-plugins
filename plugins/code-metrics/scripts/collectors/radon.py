#!/usr/bin/env python3
"""Adapter for `radon` (rubik/radon), the Python lane's native collector.

Adapter contract (design/contracts.md section 3): `probe`, `measures`,
`collect <lane> <measure> <file>...`, `install_hint`.

Two subcommands are read (probed 2026-09-05 against radon 6.0.1; the captures
in fixtures/tool-output/radon-cc.json and radon-hal.json are the reference
shapes):

  radon cc -j <files>   {file: [{type, rank, name, lineno, endline,
                        complexity, closures: [...]}]}. Closures are emitted
                        as rows of their own, so a nested function carries its
                        own range for the CRAP join. Serves `cyclomatic` and
                        `function_lines`.
  radon hal -j <files>  {file: {total: {...}, functions: {name: {...}}}}. The
                        per-function block carries no line numbers, so those
                        rows have `start_line` and `end_line` of `null` and
                        the label `no-line-range` (design T7, T12).
"""

from __future__ import annotations

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

NAME = "radon"
LANE = "python"
MEASURES = ("cyclomatic", "halstead", "function_lines")


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


def _flatten(entries: list) -> list[dict]:
    out: list[dict] = []
    for entry in entries:
        if not isinstance(entry, dict) or "lineno" not in entry:
            continue
        out.append(entry)
        out.extend(_flatten(entry.get("closures") or []))
        out.extend(_flatten(entry.get("methods") or []))
    return out


def _non_blank(path: str, start: int | None = None, end: int | None = None) -> int:
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return 0
    if start is not None and end is not None:
        lines = lines[start - 1 : end]
    return sum(1 for line in lines if line.strip())


def translate_cc(raw: str, measure: str, wanted: list[str]) -> list[dict]:
    wanted_norm = {normalize(p): p for p in wanted}
    document = json.loads(raw)
    if not isinstance(document, dict):
        raise ValueError("radon cc -j did not print an object")
    rows: list[dict] = []
    for location, entries in document.items():
        path = wanted_norm.get(normalize(location))
        if path is None or not isinstance(entries, list):
            continue
        total = _non_blank(path) if measure == "function_lines" else 0
        for entry in _flatten(entries):
            start, end = int(entry["lineno"]), int(entry["endline"])
            if measure == "cyclomatic":
                values: dict = {"cyclomatic": int(entry["complexity"])}
            else:
                inside = _non_blank(path, start, end)
                values = {
                    "function_lines": inside,
                    "function_lines_pct": round(100.0 * inside / total, 2)
                    if total
                    else None,
                }
            rows.append(
                {
                    "file": path.replace("\\", "/"),
                    "function": entry.get("name"),
                    "start_line": start,
                    "end_line": end,
                    "lane": LANE,
                    "values": values,
                    "collector": NAME,
                    "labels": [],
                }
            )
    return rows


def translate_hal(raw: str, wanted: list[str]) -> list[dict]:
    wanted_norm = {normalize(p): p for p in wanted}
    document = json.loads(raw)
    if not isinstance(document, dict):
        raise ValueError("radon hal -j did not print an object")
    rows: list[dict] = []
    for location, block in document.items():
        path = wanted_norm.get(normalize(location))
        if path is None or not isinstance(block, dict):
            continue
        functions = block.get("functions")
        if not isinstance(functions, dict):
            continue
        for function, metrics in functions.items():
            if not isinstance(metrics, dict):
                continue
            rows.append(
                {
                    "file": path.replace("\\", "/"),
                    "function": function,
                    "start_line": None,
                    "end_line": None,
                    "lane": LANE,
                    "values": {
                        "halstead_difficulty": metrics.get("difficulty"),
                        "halstead_volume": metrics.get("volume"),
                        "halstead_effort": metrics.get("effort"),
                    },
                    "collector": NAME,
                    "labels": ["no-line-range"],
                }
            )
    return rows


def collect(lane: str, measure: str, files: list[str]) -> int:
    if lane != LANE or measure not in MEASURES:
        print(f"{NAME}.py: cannot collect {lane}/{measure}", file=sys.stderr)
        return 2
    exe = shutil.which(NAME)
    if not exe:
        print(f"{NAME} not on PATH", file=sys.stderr)
        return 3
    subcommand = "hal" if measure == "halstead" else "cc"
    result = subprocess.run(
        [exe, subcommand, "-j", *files], capture_output=True, text=True, check=False
    )
    try:
        if measure == "halstead":
            rows = translate_hal(result.stdout, files)
        else:
            rows = translate_cc(result.stdout, measure, files)
    except (ValueError, TypeError, KeyError) as exc:
        print(
            f"{NAME}.py: no parseable {NAME} {subcommand} output ({exc}); "
            f"stderr: {result.stderr.strip()}",
            file=sys.stderr,
        )
        return 3
    for row in rows:
        print(json.dumps(row))
    return 0


def measures() -> None:
    for measure in MEASURES:
        print(f"{LANE}/{measure}")


INSTALL_HINT = "radon: https://github.com/rubik/radon (pip install radon)"


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
