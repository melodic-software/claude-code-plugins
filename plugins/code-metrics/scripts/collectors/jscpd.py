#!/usr/bin/env python3
"""Adapter for `jscpd`, the clone detector behind every duplication lane.

Adapter contract (design/contracts.md section 3): `probe`, `measures`,
`collect <lane> <measure> <file>...`, `install_hint`.

jscpd 5 is a Rust binary that only writes its report to a file, so `collect`
runs it with `--reporters json --output <tmpdir>`, reads
`<tmpdir>/jscpd-report.json`, prints the translated rows, and deletes the
temporary directory (probed 2026-09-05 against jscpd 5.1.2). `--absolute` is
passed because jscpd otherwise names files relative to the common ancestor of
its inputs, which collapses two vendored copies that share a basename into one
indistinguishable name; the absolute paths are made relative to the working
directory here. jscpd 4 wrote a different document under the same name and is
not translated by this file.

Each duplicate becomes one clone-group row: `file` and `function` are null,
`instances[]` carries every copy with its line range, and `values` carries
`lines` and `tokens`. Tunables arrive as environment variables the calling
skill exports from the resolved configuration:

  CODE_METRICS_DUP_MIN_TOKENS  jscpd --min-tokens  (default 50)
  CODE_METRICS_DUP_MIN_LINES   jscpd --min-lines   (default 5)
  CODE_METRICS_DUP_IGNORE      jscpd --ignore, comma-separated globs (default none)

jscpd's own exit code is not read: it exits non-zero when a `--threshold` or
`--exit-code` run finds clones, and this adapter passes neither, so the report
file is the only success signal (design T1: a collector succeeds when it
produced parseable output).
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

MIN_PYTHON = (3, 9)
NAME = "jscpd"
REPORT_BASENAME = "jscpd-report.json"
DEFAULT_MIN_TOKENS = "50"
DEFAULT_MIN_LINES = "5"


def _normalize(path: str) -> str:
    path = path.replace("\\", "/")
    if os.path.isabs(path):
        try:
            path = os.path.relpath(path, os.getcwd())
        except ValueError:
            return path
    while path.startswith("./"):
        path = path[2:]
    return path.replace("\\", "/")


def _resolve() -> str | None:
    exe = shutil.which(NAME)
    if exe:
        return exe
    local = os.path.join(".", "node_modules", ".bin", NAME)
    if os.path.isfile(local) and os.access(local, os.X_OK):
        return local
    return None


def probe() -> int:
    exe = _resolve()
    if not exe:
        print("jscpd not on PATH or in ./node_modules/.bin", file=sys.stderr)
        return 1
    try:
        out = subprocess.run(
            [exe, "--version"], capture_output=True, text=True, check=False
        )
    except OSError as exc:
        print(f"jscpd --version failed: {exc}", file=sys.stderr)
        return 1
    match = re.search(r"(\d+\.\d+(?:\.\d+)?)", out.stdout + out.stderr)
    print(match.group(1) if match else "unknown-version")
    return 0


def _instance(entry: dict) -> dict:
    return {
        "file": _normalize(str(entry.get("name", ""))),
        "start_line": entry.get("start"),
        "end_line": entry.get("end"),
    }


def translate(raw: str, lane: str) -> list[dict]:
    document = json.loads(raw)
    rows: list[dict] = []
    for duplicate in document.get("duplicates", []):
        instances = [
            _instance(duplicate[key])
            for key in ("firstFile", "secondFile")
            if isinstance(duplicate.get(key), dict)
        ]
        if not instances:
            continue
        rows.append(
            {
                "file": None,
                "function": None,
                "lane": lane,
                "instances": instances,
                "values": {
                    "lines": duplicate.get("lines"),
                    "tokens": duplicate.get("tokens"),
                },
                "collector": NAME,
                "labels": ["token-based"],
            }
        )
    return rows


def _command(exe: str, output: str, files: list[str]) -> list[str]:
    command = [
        exe,
        "--reporters",
        "json",
        "--output",
        output,
        "--min-tokens",
        os.environ.get("CODE_METRICS_DUP_MIN_TOKENS") or DEFAULT_MIN_TOKENS,
        "--min-lines",
        os.environ.get("CODE_METRICS_DUP_MIN_LINES") or DEFAULT_MIN_LINES,
        "--absolute",
        "--silent",
    ]
    ignore = os.environ.get("CODE_METRICS_DUP_IGNORE") or ""
    if ignore.strip():
        command += ["--ignore", ignore.strip()]
    return command + files


def collect(lane: str, measure: str, files: list[str]) -> int:
    if measure != "duplication":
        print(f"jscpd.py: cannot collect {measure}", file=sys.stderr)
        return 2
    exe = _resolve()
    if not exe:
        print("jscpd not on PATH or in ./node_modules/.bin", file=sys.stderr)
        return 3
    output = tempfile.mkdtemp(prefix="code-metrics-jscpd-")
    try:
        result = subprocess.run(
            _command(exe, output, files),
            capture_output=True,
            text=True,
            check=False,
        )
        report = os.path.join(output, REPORT_BASENAME)
        try:
            with open(report, encoding="utf-8") as handle:
                rows = translate(handle.read(), lane)
        except (OSError, json.JSONDecodeError, ValueError, TypeError) as exc:
            print(
                f"jscpd.py: no parseable {REPORT_BASENAME} ({exc}); "
                f"stderr: {result.stderr.strip()}",
                file=sys.stderr,
            )
            return 3
    finally:
        shutil.rmtree(output, ignore_errors=True)
    for row in rows:
        print(json.dumps(row))
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        print(
            "usage: jscpd.py probe|measures|collect <lane> <measure> <file>...|install_hint",
            file=sys.stderr,
        )
        return 2
    verb, rest = argv[0], argv[1:]
    if verb == "probe":
        return probe()
    if verb == "measures":
        print("*/duplication")
        return 0
    if verb == "install_hint":
        print(
            "jscpd: https://github.com/kucherenko/jscpd (npm install -g jscpd, or add it to the repository's devDependencies); this plugin never installs it"
        )
        return 0
    if verb == "collect":
        if len(rest) < 2:
            print("usage: jscpd.py collect <lane> <measure> <file>...", file=sys.stderr)
            return 2
        return collect(rest[0], rest[1], rest[2:])
    print(f"jscpd.py: unknown verb {verb}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print("jscpd.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
