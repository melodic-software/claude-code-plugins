#!/usr/bin/env python3
"""Adapter for `mypy --any-exprs-report`, the Python type-debt collector.

Adapter contract (design/contracts.md section 3): `probe`, `measures`,
`collect <lane> <measure> <file>...`, `install_hint`.

mypy writes `any-exprs.txt` into the directory given to `--any-exprs-report`:
a fixed-width table with the columns Name, Anys, Exprs, Coverage, one row per
module, and a `Total` row. This adapter reads the `Total` row and prints one
per-lane row (`file` and `function` are `null`, per the report contract). The
report directory is a temporary one, created and removed here, because mypy
overwrites the whole directory.

Facts probed against mypy 1.19.1 (its documentation and source at that tag,
unchanged at 2.3.1) and replayed by fixtures/tool-output/mypy-any-exprs.txt and
mypy-any-exprs-aborted.txt:

- the table is whitespace-aligned and the Coverage column carries a trailing
  percent sign;
- mypy exits 1 on any type error and still writes the report (design T1), so
  exit 1 with a readable report is exit 0 here, with the row labelled
  `mypy-reported-errors`;
- mypy exits 2 on a blocking error (a duplicate module name, a usage or config
  error) before analysing anything, and still writes a report whose only row
  is `Total 0 0 100.00%`. Nothing was measured, so exit 2 is the adapter
  contract's exit 4 (the tool resolved but cannot run on these files) with
  mypy's stderr relayed, never a 100% row. An unwritten or unreadable report on
  any other exit is exit 3;
- a Total row with 0 expressions is `type_coverage_pct: null`, because nothing
  was counted; mypy's 100.00% for an empty build is not a measurement;
- `--explicit-package-bases` derives each module name from its path relative
  to the working directory (or a MYPYPATH entry), so two same-named files under
  identifier-named directories (`a/foo.py`, `b/foo.py`) no longer collide. The
  walk stops at a directory whose name is not a Python identifier, so
  same-named files under two hyphenated directories still collide and reach the
  exit-4 path with mypy's message;
- `--cache-dir os.devnull` is mypy's documented "disable caching" value (mypy
  compares the option to os.devnull by string equality, `/dev/null` on POSIX
  and `nul` on Windows), so no `.mypy_cache` is written into the consumer's
  tree; over this repository's 179 files caching saved nothing (6.8s without a
  cache against 8.2s with a warm one).

The percentage is mypy's own Coverage figure over expressions, which is not the
`type-coverage` identifier ratio the TypeScript lane reports. The two are never
compared with each other.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

from adapter_paths import files_from

MIN_PYTHON = (3, 9)
NAME = "mypy-report"
TOOL = "mypy"
MEASURE = "type_coverage"
LANE = "python"
# mypy's exit for a blocking error (duplicate module, usage or config error):
# it stops before analysing anything and its report carries no measurement.
FATAL_EXIT = 2


def probe() -> int:
    exe = shutil.which(TOOL)
    if not exe:
        print(f"{TOOL} not on PATH", file=sys.stderr)
        return 1
    try:
        out = subprocess.run(
            [exe, "--version"], capture_output=True, text=True, check=False
        )
    except OSError as exc:
        print(f"{TOOL} --version failed: {exc}", file=sys.stderr)
        return 1
    match = re.search(r"(\d+\.\d+(?:\.\d+)?)", out.stdout + out.stderr)
    print(match.group(1) if match else "unknown-version")
    return 0


def parse_total(table: str) -> tuple[int, int, float]:
    """Return (anys, exprs, coverage percent) from the table's `Total` row."""
    for line in table.splitlines():
        fields = line.split()
        if len(fields) != 4 or fields[0] != "Total":
            continue
        return (
            int(fields[1]),
            int(fields[2]),
            float(fields[3].rstrip("%")),
        )
    raise ValueError("the any-exprs report has no Total row")


def collect(lane: str, measure: str, files: list[str]) -> int:
    if measure != MEASURE:
        print(f"{NAME}.py: cannot collect {measure}", file=sys.stderr)
        return 2
    exe = shutil.which(TOOL)
    if not exe:
        print(f"{TOOL} not on PATH", file=sys.stderr)
        return 3
    report_dir = tempfile.mkdtemp(prefix="code-metrics-mypy-")
    try:
        result = subprocess.run(
            [
                exe,
                "--any-exprs-report",
                report_dir,
                "--no-error-summary",
                "--explicit-package-bases",
                "--cache-dir",
                os.devnull,
                *files,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == FATAL_EXIT:
            # A blocking error stopped mypy before analysis; the report it still
            # wrote is empty, so there is no measurement to read. The tool
            # resolved but cannot run on these files: the dispatcher writes an
            # `unavailable` row carrying this reason (exit 4).
            # mypy prints its error lines to stdout and usage errors to
            # stderr, so the reason carries both.
            said = " ".join(
                part.strip().replace("\n", " ")
                for part in (result.stdout, result.stderr)
                if part.strip()
            )
            print(
                f"mypy could not analyse these files (exit {FATAL_EXIT}): {said}",
                file=sys.stderr,
            )
            return 4
        report = os.path.join(report_dir, "any-exprs.txt")
        try:
            with open(report, encoding="utf-8") as handle:
                table = handle.read()
        except OSError:
            print(
                f"{NAME}.py: mypy wrote no any-exprs report (exit {result.returncode}); "
                f"stderr: {result.stderr.strip()}",
                file=sys.stderr,
            )
            return 3
    finally:
        shutil.rmtree(report_dir, ignore_errors=True)
    try:
        anys, exprs, coverage = parse_total(table)
    except ValueError as exc:
        print(f"{NAME}.py: unparsable report ({exc})", file=sys.stderr)
        return 3
    row = {
        "file": None,
        "function": None,
        "lane": lane,
        "values": {
            "any_expressions": anys,
            "expressions_total": exprs,
            "type_coverage_pct": coverage if exprs else None,
        },
        "collector": NAME,
        "labels": ["mypy-reported-errors"] if result.returncode != 0 else [],
    }
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
            "mypy: https://mypy.readthedocs.io (pip install mypy, pipx install mypy, or uv tool install mypy)"
        )
        return 0
    if verb == "collect":
        if len(rest) < 2:
            print(
                f"usage: {NAME}.py collect <lane> <measure> <file>...", file=sys.stderr
            )
            return 2
        return collect(rest[0], rest[1], files_from(rest[2:]))
    print(f"{NAME}.py: unknown verb {verb}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print(
            "mypy-report.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
