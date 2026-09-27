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
`--version`, falls back to the version `go install` stamped into the binary
(`go version -m`), prints `version unavailable (gocognit has no version flag)`
when nothing answers, and still exits 0 because the tool itself resolved.
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
    version_in,
    version_output,
)

NAME = "gocognit"
LANE = "go"
MEASURE = "cognitive"


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
    print(module_version(exe) or "version unavailable (gocognit has no version flag)")
    return 0


def module_version(exe: str) -> str | None:
    """The version stamped into the binary by `go install`, read with
    `go version -m`, whose `mod` line names the module and its version. A
    binary built some other way, or a machine with no `go`, yields nothing."""
    go = shutil.which("go")
    if not go:
        return None
    try:
        out = subprocess.run(
            [go, "version", "-m", exe],
            capture_output=True,
            text=True,
            check=False,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    for line in out.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "mod" and "gocognit" in parts[1]:
            found = version_in(parts[2])
            if found is not None:
                return found
    return None


def translate(raw: str, lane: str, wanted: list[str]) -> list[dict]:
    wanted_norm = {normalize(p): p for p in wanted}
    document = json.loads(raw)
    if not isinstance(document, list):
        raise ValueError("gocognit -json did not print an array")
    rows: list[dict] = []
    for entry in document:
        if not isinstance(entry, dict):
            continue
        position = entry.get("Pos") or {}
        path = wanted_norm.get(normalize(position.get("Filename", "")))
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
    except (ValueError, TypeError, AttributeError) as exc:
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


INSTALL_HINT = "gocognit: https://github.com/uudashr/gocognit (go install github.com/uudashr/gocognit/cmd/gocognit@latest)"


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
