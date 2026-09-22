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
had no `eslint-plugin-sonarjs`, so the file is labeled unverified.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

from adapter_paths import (
    dispatch,
    match_path,
    normalize,
    require_python,
    version_or_unknown,
    version_output,
)

NAME = "sonarjs"
LANE = "typescript"
MEASURE = "cognitive"
RULE = "sonarjs/cognitive-complexity"
PLUGIN = "eslint-plugin-sonarjs"
COGNITIVE_MESSAGE = re.compile(r"Cognitive Complexity from (?P<value>\d+)")
DECLARED_NAME = re.compile(r"(?:function|class)\s+([A-Za-z_$][A-Za-z0-9_$]*)")


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
    output = version_output(exe, "eslint")
    if output is None:
        return 1
    print(version_or_unknown(output))
    return 0


def translate(raw: str, lane: str, wanted: list[str]) -> list[dict]:
    wanted_norm = {normalize(p): p for p in wanted}
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
    except (ValueError, TypeError) as exc:
        print(
            f"{NAME}.py: no parseable eslint output ({exc}); "
            f"stderr: {result.stderr.strip()}",
            file=sys.stderr,
        )
        return 3
    for row in rows:
        print(json.dumps(row))
    return 0


def measures() -> None:
    print(f"{LANE}/{MEASURE}")


INSTALL_HINT = (
    "eslint-plugin-sonarjs: https://github.com/SonarSource/eslint-plugin-sonarjs "
    "(npm install --save-dev eslint eslint-plugin-sonarjs)"
)


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
