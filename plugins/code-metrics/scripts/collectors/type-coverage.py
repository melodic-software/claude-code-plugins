#!/usr/bin/env python3
"""Adapter for `type-coverage`, the TypeScript type-debt collector.

Adapter contract (design/contracts.md section 3): `probe`, `measures`,
`collect <lane> <measure> <file>...`, `install_hint`.

The measure is type-coverage's own ratio, the count of identifiers whose type
is not `any` over the total identifier count. It is not mypy's Any-expression
coverage, and the two percentages are never compared with each other.

Facts verified against type-coverage 2.30.1 and typescript 5.9.3 on
2026-09-05, and replayed by fixtures/tool-output/type-coverage.json:

- `--json-output` is a boolean flag: the JSON goes to stdout, with
  `correctCount`, `totalCount`, `percent` (`null` when nothing was counted),
  and, only when `--detail` is also passed, `details[]`, one entry per `any`
  location. So `collect` runs `type-coverage --detail --json-output -- <files>`
  and `any_count` is `null` when the tool listed no locations at all.
- files after `--` restrict the run to those files, so the row is the scope the
  dispatcher asked for rather than a project-wide figure. The tool still reads
  the project's `tsconfig.json`; without one it counts nothing and reports
  `percent: null`, which stays `null` here rather than becoming zero.
- the tool crashes (`ts.SyntaxKind` undefined) when `typescript` does not
  resolve from the project, so `probe` requires both the binary and a
  resolvable `typescript` (design T1). typescript 7's JS entry point does not
  carry the API type-coverage 2.30.1 reads either; that is an upstream pairing
  question, not something the probe can distinguish, and the crash surfaces as
  exit 3 with the tool's own stderr.

The binary resolves from `./node_modules/.bin/type-coverage` first, so a
project's own pinned version wins over anything on `PATH`. Nothing is ever
installed or fetched.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

MIN_PYTHON = (3, 9)
NAME = "type-coverage"
MEASURE = "type_coverage"
LANE = "typescript"
LOCAL_BIN = os.path.join("node_modules", ".bin", "type-coverage")
NO_TYPESCRIPT = "type-coverage needs a resolvable typescript (the probe found none)"


def resolve_binary() -> str | None:
    if os.path.isfile(LOCAL_BIN) and os.access(LOCAL_BIN, os.X_OK):
        return os.path.abspath(LOCAL_BIN)
    return shutil.which(NAME)


def typescript_resolves() -> bool:
    """True when `typescript` resolves from the current directory."""
    if os.path.isfile(os.path.join("node_modules", "typescript", "package.json")):
        return True
    node = shutil.which("node")
    if not node:
        return False
    try:
        result = subprocess.run(
            [node, "-e", "require.resolve('typescript')"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return False
    return result.returncode == 0


def probe() -> int:
    exe = resolve_binary()
    if not exe:
        print(
            f"{NAME} not on PATH and not in ./{LOCAL_BIN.replace(os.sep, '/')}",
            file=sys.stderr,
        )
        return 1
    if not typescript_resolves():
        print(NO_TYPESCRIPT, file=sys.stderr)
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


def translate(raw: str, lane: str) -> dict:
    payload = json.loads(raw)
    percent = payload.get("percent")
    details = payload.get("details")
    return {
        "file": None,
        "function": None,
        "lane": lane,
        "values": {
            "type_coverage_pct": float(percent) if percent is not None else None,
            "typed_identifiers": payload.get("correctCount"),
            "total_identifiers": payload.get("totalCount"),
            "any_count": len(details) if isinstance(details, list) else None,
        },
        "collector": NAME,
        "labels": [],
    }


def collect(lane: str, measure: str, files: list[str]) -> int:
    if measure != MEASURE:
        print(f"{NAME}.py: cannot collect {measure}", file=sys.stderr)
        return 2
    exe = resolve_binary()
    if not exe:
        print(f"{NAME} not on PATH", file=sys.stderr)
        return 3
    result = subprocess.run(
        [exe, "--detail", "--json-output", "--", *files],
        capture_output=True,
        text=True,
        check=False,
    )
    try:
        row = translate(result.stdout, lane)
    except (json.JSONDecodeError, ValueError, TypeError) as exc:
        print(
            f"{NAME}.py: unparsable {NAME} output ({exc}); stderr: {result.stderr.strip()}",
            file=sys.stderr,
        )
        return 3
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
        # The dispatcher relays this line when the probe fails, so it names
        # both halves of the requirement, not just the binary.
        print(
            "type-coverage: npm install --save-dev type-coverage typescript "
            "(https://github.com/plantain-00/type-coverage; type-coverage needs a resolvable typescript)"
        )
        return 0
    if verb == "collect":
        if len(rest) < 2:
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
            "type-coverage.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
