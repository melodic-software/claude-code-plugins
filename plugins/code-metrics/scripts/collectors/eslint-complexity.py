#!/usr/bin/env python3
"""Adapter for ESLint's core `complexity` rule, the TypeScript/JavaScript lane.

Adapter contract (design/contracts.md section 3): `probe`, `measures`,
`collect <lane> <measure> <file>...`, `install_hint`.

`probe` resolves `eslint` on PATH first, then `node_modules/.bin/eslint`
under the current working directory, and never installs anything (design
T14). `collect` runs

    eslint --format json --rule {"complexity": ["error", 0]} <files>

so every function reports its own number, and reads the `has a complexity of
N` message with its `line`. ESLint exits 1 whenever it reports, which at a
maximum of 0 is every run: that exit code is the success path, because a
collector succeeds when it produced parseable output (design T1).

The rule reports the line a function starts on and no end line, so rows carry
`end_line: null` and the label `start-line-only`; `audit-coverage` reads that
label and reports `crap: not-applicable` for the lane rather than a null
(design T7). The consumer's own ESLint configuration still applies, so
messages from other rules appear in the same document and are ignored here.

The capture in fixtures/tool-output/eslint.json is the reference shape: the
envelope and the message text come from a live ESLint 10.1.0 run, on a
JavaScript equivalent of the TypeScript fixture because the sandbox has no
TypeScript parser for ESLint, so the file is labelled unverified.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

MIN_PYTHON = (3, 9)
NAME = "eslint-complexity"
LANE = "typescript"
MEASURE = "cyclomatic"
RULE = "complexity"
COMPLEXITY_MESSAGE = re.compile(r"^(?P<what>.+?) has a complexity of (?P<value>\d+)")
QUOTED_NAME = re.compile(r"'([^']+)'")


def _normalize(path: str) -> str:
    path = path.replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return os.path.normpath(path).replace("\\", "/")


def resolve_eslint() -> str | None:
    exe = shutil.which("eslint")
    if exe:
        return exe
    local = os.path.join("node_modules", ".bin", "eslint")
    if os.path.isfile(local) and os.access(local, os.X_OK):
        return os.path.abspath(local)
    return None


def probe() -> int:
    exe = resolve_eslint()
    if not exe:
        print("eslint not on PATH or in ./node_modules/.bin", file=sys.stderr)
        return 1
    try:
        out = subprocess.run(
            [exe, "--version"], capture_output=True, text=True, check=False
        )
    except OSError as exc:
        print(f"eslint --version failed: {exc}", file=sys.stderr)
        return 1
    match = re.search(r"(\d+\.\d+(?:\.\d+)?)", out.stdout + out.stderr)
    print(match.group(1) if match else "unknown-version")
    return 0


def match_path(location: str, wanted_norm: dict[str, str]) -> str | None:
    """ESLint prints absolute paths; map one back to the path the dispatcher
    passed, by exact match first and then by path-segment suffix."""
    norm = _normalize(location)
    if norm in wanted_norm:
        return wanted_norm[norm]
    for key, original in wanted_norm.items():
        if norm.endswith("/" + key):
            return original
    return None


def translate(raw: str, lane: str, wanted: list[str]) -> list[dict]:
    wanted_norm = {_normalize(p): p for p in wanted}
    document = json.loads(raw)
    if not isinstance(document, list):
        raise ValueError("eslint --format json did not print an array")
    rows: list[dict] = []
    for result in document:
        if not isinstance(result, dict):
            continue
        path = match_path(result.get("filePath", ""), wanted_norm)
        if path is None:
            continue
        for message in result.get("messages") or []:
            if message.get("ruleId") != RULE:
                continue
            match = COMPLEXITY_MESSAGE.match(message.get("message", ""))
            if not match:
                continue
            what = match.group("what")
            named = QUOTED_NAME.search(what)
            rows.append(
                {
                    "file": path.replace("\\", "/"),
                    "function": named.group(1) if named else what,
                    "start_line": message.get("line"),
                    "end_line": None,
                    "lane": lane,
                    "values": {MEASURE: int(match.group("value"))},
                    "collector": NAME,
                    "labels": ["start-line-only"],
                }
            )
    return rows


def collect(lane: str, measure: str, files: list[str]) -> int:
    if lane != LANE or measure != MEASURE:
        print(f"{NAME}.py: cannot collect {lane}/{measure}", file=sys.stderr)
        return 2
    exe = resolve_eslint()
    if not exe:
        print("eslint not on PATH or in ./node_modules/.bin", file=sys.stderr)
        return 3
    result = subprocess.run(
        [
            exe,
            "--format",
            "json",
            "--rule",
            json.dumps({RULE: ["error", 0]}),
            *files,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    try:
        rows = translate(result.stdout, lane, files)
    except (json.JSONDecodeError, ValueError, TypeError) as exc:
        print(
            f"{NAME}.py: no parseable eslint output ({exc}); "
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
            "eslint: https://eslint.org (npm install --save-dev eslint; the core complexity rule needs no plugin)"
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
            "eslint-complexity.py needs Python %d.%d or later" % MIN_PYTHON,
            file=sys.stderr,
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
