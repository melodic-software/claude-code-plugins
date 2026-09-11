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
  location (`filePath`, 0-based `line` and `character`, the identifier
  `text`). So `collect` runs
  `type-coverage --detail --json-output --show-relative-path -- <files>` and
  the lane row's `any_count` is `null` when the tool listed no locations at
  all.
- `--show-relative-path` makes `filePath` relative to the working directory
  (the tool resolves it against the cwd otherwise), which is how the
  dispatcher's scope paths are written; both sides are compared as absolute,
  normcased paths, so a Windows `filePath` with backslashes still matches.
- the CLI exposes no per-file denominator (its core's `fileCounts` option is
  never passed), so a file row carries `any_count` alone, the occurrences
  listed for that file, with the other three values `null`.
- the tool counts only the files of its `tsconfig.json` program and does not
  say which those are (verified on 2.30.1: a file outside `include`
  contributes nothing and is not named), so the program's file set is read
  through the project's own `typescript` (one `node` call: `findConfigFile`,
  `parseJsonConfigFileContent`, `createProgram`, the source files outside
  `node_modules`; this is the set core's `lint` iterates). A scope file in the
  program with no listed occurrence reads `any_count: 0`, a measured zero; a
  scope file outside it gets no row and is counted in a stderr note the
  dispatcher relays as the run row's reason. When that call fails, only scope
  files with a listed occurrence get a row and the note says why. No file
  rows are emitted when `totalCount` is 0.
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

from adapter_paths import files_from

MIN_PYTHON = (3, 9)
NAME = "type-coverage"
MEASURE = "type_coverage"
LANE = "typescript"
LOCAL_BIN = os.path.join("node_modules", ".bin", "type-coverage")
NO_TYPESCRIPT = "type-coverage needs a resolvable typescript (the probe found none)"
# Prints the tsconfig program's source files (absolute paths, dependencies
# included) as a JSON array, or `null` when no tsconfig.json resolves from the
# working directory, through the same `typescript` the tool itself uses. The
# `node_modules` exclusion is applied here, by path segment.
PROGRAM_SCRIPT = """
const ts = require('typescript');
const path = require('path');
const config = ts.findConfigFile(process.cwd(), ts.sys.fileExists);
if (!config) { console.log('null'); process.exit(0); }
const read = ts.readConfigFile(config, ts.sys.readFile);
const parsed = ts.parseJsonConfigFileContent(read.config || {}, ts.sys, path.dirname(config));
const program = ts.createProgram(parsed.fileNames, parsed.options);
console.log(JSON.stringify(program.getSourceFiles().map(f => f.fileName)));
"""


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


def _key(path: str) -> str:
    return os.path.normcase(os.path.abspath(path))


def _under_node_modules(path: str) -> bool:
    """True when a whole path segment is `node_modules`, the dependency tree
    the tool itself leaves out; a file whose name merely contains the string
    (`src/node_modules_helper.ts`) is a source file and stays."""
    return "node_modules" in re.split(r"[\\/]", path)


def _row(lane: str, file: str | None, values: dict, labels: list[str]) -> dict:
    return {
        "file": file,
        "function": None,
        "lane": lane,
        "values": values,
        "collector": NAME,
        "labels": labels,
    }


def program_files() -> tuple[set[str] | None, str]:
    """The tsconfig program's files as match keys, or None and why not."""
    node = shutil.which("node")
    if not node:
        return None, "node is not on PATH"
    try:
        result = subprocess.run(
            [node, "-e", PROGRAM_SCRIPT], capture_output=True, text=True, check=False
        )
    except OSError as exc:
        return None, f"node failed to start: {exc}"
    if result.returncode != 0:
        said = result.stderr.strip().splitlines() or [
            "node exited " + str(result.returncode)
        ]
        return None, said[-1][:200]
    try:
        listed = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None, "the program listing was not JSON"
    if not isinstance(listed, list):
        return None, "no tsconfig.json resolves from the working directory"
    return {
        _key(str(name)) for name in listed if not _under_node_modules(str(name))
    }, ""


def translate(
    raw: str,
    lane: str,
    files: list[str] | None = None,
    program: set[str] | None = None,
    why_no_program: str = "",
) -> tuple[list[dict], list[str]]:
    """The rows for one capture, the lane row first, and the notes for
    stderr: a row per scope file in the tsconfig program when the tool counted
    anything; scope files outside the program are named in a note, never
    given a 0."""
    payload = json.loads(raw)
    percent = payload.get("percent")
    details = payload.get("details")
    notes: list[str] = []
    file_rows: list[dict] = []
    if payload.get("totalCount") and isinstance(details, list):
        listed: dict[str, int] = {}
        for entry in details:
            key = _key(str(entry.get("filePath", "")))
            listed[key] = listed.get(key, 0) + 1
        outside: list[str] = []
        for path in files or []:
            key = _key(path)
            if program is None:
                if key not in listed:
                    continue
            elif key not in program:
                outside.append(path)
                continue
            file_rows.append(
                _row(
                    lane,
                    path,
                    {
                        "type_coverage_pct": None,
                        "typed_identifiers": None,
                        "total_identifiers": None,
                        "any_count": listed.get(key, 0),
                    },
                    [],
                )
            )
        if program is None:
            notes.append(
                f"the tsconfig program could not be read ({why_no_program}); "
                "only scope files with a listed occurrence have a row"
            )
        elif outside:
            shown = ", ".join(outside[:3]) + (", ..." if len(outside) > 3 else "")
            notes.append(
                f"{len(outside)} scope file(s) are outside the tsconfig program "
                f"and were not measured: {shown}"
            )
    lane_row = _row(
        lane,
        None,
        {
            "type_coverage_pct": float(percent) if percent is not None else None,
            "typed_identifiers": payload.get("correctCount"),
            "total_identifiers": payload.get("totalCount"),
            "any_count": len(details) if isinstance(details, list) else None,
        },
        ["lane-total"],
    )
    return [lane_row, *file_rows], notes


def collect(lane: str, measure: str, files: list[str]) -> int:
    if measure != MEASURE:
        print(f"{NAME}.py: cannot collect {measure}", file=sys.stderr)
        return 2
    exe = resolve_binary()
    if not exe:
        print(f"{NAME} not on PATH", file=sys.stderr)
        return 3
    result = subprocess.run(
        [exe, "--detail", "--json-output", "--show-relative-path", "--", *files],
        capture_output=True,
        text=True,
        check=False,
    )
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        print(
            f"{NAME}.py: unparsable {NAME} output ({exc}); stderr: {result.stderr.strip()}",
            file=sys.stderr,
        )
        return 3
    program: set[str] | None = None
    why = ""
    if isinstance(payload, dict) and payload.get("totalCount"):
        # Only a run that counted something needs to know which files the
        # program holds; the no-tsconfig case never reaches node.
        program, why = program_files()
    try:
        rows, notes = translate(result.stdout, lane, files, program, why)
    except (ValueError, TypeError, AttributeError) as exc:
        print(f"{NAME}.py: unparsable {NAME} output ({exc})", file=sys.stderr)
        return 3
    for row in rows:
        print(json.dumps(row))
    if notes:
        print("; ".join(notes), file=sys.stderr)
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
        return collect(rest[0], rest[1], files_from(rest[2:]))
    print(f"{NAME}.py: unknown verb {verb}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print(
            "type-coverage.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
