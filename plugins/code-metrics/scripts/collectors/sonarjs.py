#!/usr/bin/env python3
"""Adapter for the `eslint-plugin-sonarjs` cognitive-complexity rule (TS/JS).

Adapter contract (design/contracts.md section 3): `probe`, `measures`,
`collect <lane> <measure> <file>...`, `install_hint`.

`probe` needs both halves and never installs either (design T14):

  1. `eslint`, on PATH first, then `node_modules/.bin/eslint` under the
     current working directory.
  2. `eslint-plugin-sonarjs`, looked up as
     `node_modules/eslint-plugin-sonarjs/package.json` in the working
     directory and then in each ancestor directory. That is the same walk
     ESLint's flat-config `--plugin` option uses to resolve a plugin name
     relative to the working directory, now that `--resolve-plugins-relative-to`
     is gone.

`collect` runs

    eslint --format json --plugin sonarjs
           --rule {"sonarjs/cognitive-complexity": ["error", 0]} <files>

so every function reports, and reads `Cognitive Complexity from N` out of the
message with its `line`. ESLint exits 1 whenever it reports, which is the
success path (design T1). The rule reports no end line, so rows carry
`end_line: null` and the label `start-line-only` (design T7).

Cognitive complexity is Campbell's measure (SonarSource); no standard sets a
threshold for it, which is why the bundled reference is `null`.

The capture in fixtures/tool-output/sonarjs.json is written to ESLint's
documented JSON shape with the rule's documented message text; the sandbox
had no `eslint-plugin-sonarjs`, so the file is labelled unverified.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

MIN_PYTHON = (3, 9)
NAME = "sonarjs"
LANE = "typescript"
MEASURE = "cognitive"
RULE = "sonarjs/cognitive-complexity"
PLUGIN = "eslint-plugin-sonarjs"
COGNITIVE_MESSAGE = re.compile(r"Cognitive Complexity from (?P<value>\d+)")
DECLARED_NAME = re.compile(r"(?:function|class)\s+([A-Za-z_$][A-Za-z0-9_$]*)")


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


def resolve_plugin() -> str | None:
    directory = os.path.abspath(os.getcwd())
    while True:
        manifest = os.path.join(directory, "node_modules", PLUGIN, "package.json")
        if os.path.isfile(manifest):
            return manifest
        parent = os.path.dirname(directory)
        if parent == directory:
            return None
        directory = parent


def probe() -> int:
    exe = resolve_eslint()
    if not exe:
        print("eslint not on PATH or in ./node_modules/.bin", file=sys.stderr)
        return 1
    if not resolve_plugin():
        print(
            f"{PLUGIN} not found in node_modules under the working directory or its parents",
            file=sys.stderr,
        )
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
            match = COGNITIVE_MESSAGE.search(message.get("message", ""))
            if not match:
                continue
            rows.append(
                {
                    "file": path.replace("\\", "/"),
                    "function": function_name(result, message),
                    "start_line": message.get("line"),
                    "end_line": None,
                    "lane": lane,
                    "values": {MEASURE: int(match.group("value"))},
                    "collector": NAME,
                    "labels": ["start-line-only"],
                }
            )
    return rows


def function_name(result: dict, message: dict) -> str | None:
    """The rule's message names no function, so read a declared name off the
    reported line when ESLint included the file's `source`, and report `null`
    otherwise: an anonymous function has no name to print, and inventing one
    would be worse than none."""
    source = result.get("source")
    line = message.get("line")
    if not isinstance(source, str) or not isinstance(line, int):
        return None
    lines = source.splitlines()
    if not 1 <= line <= len(lines):
        return None
    declared = DECLARED_NAME.search(lines[line - 1])
    return declared.group(1) if declared else None


def collect(lane: str, measure: str, files: list[str]) -> int:
    if lane != LANE or measure != MEASURE:
        print(f"{NAME}.py: cannot collect {lane}/{measure}", file=sys.stderr)
        return 2
    exe = resolve_eslint()
    if not exe or not resolve_plugin():
        print(f"eslint with {PLUGIN} did not resolve", file=sys.stderr)
        return 3
    result = subprocess.run(
        [
            exe,
            "--format",
            "json",
            "--plugin",
            "sonarjs",
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
            "eslint-plugin-sonarjs: https://github.com/SonarSource/eslint-plugin-sonarjs "
            "(npm install --save-dev eslint eslint-plugin-sonarjs)"
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
        print("sonarjs.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
