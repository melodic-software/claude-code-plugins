#!/usr/bin/env python3
"""Adapter for PMD CPD, an alternative clone detector for the JVM-shaped setup.

Adapter contract (design/contracts.md section 3): `probe`, `measures`,
`collect <lane> <measure> <file>...`, `install_hint`.

CPD sits after `jscpd` on `scripts/collector-ladder.tsv` for the TypeScript,
Python, Go, and C# lanes (never Bash: CPD has no shell language), so it runs
only when `jscpd` does not resolve and `pmd` does. A repository that already
runs PMD and wants its numbers first puts it ahead through the configuration
override `lanes.<lane>.collectors.duplication: [cpd, jscpd]`, which is
validated against the ladder file.

Assumed CLI form, from the PMD 7 documentation read 2026-09-05 and unverified
against a live run:

    pmd cpd --minimum-tokens N --format xml --language <lang> --file-list <file>

`--file-list` holds one path per line; the XML report goes to stdout with the
namespaced `pmd-cpd` root documented in the CPD report formats page, one
`duplication` element per clone group carrying `lines` and `tokens` with one
`file` child per instance (`path`, `line`, `endline`). CPD exits 4 when it
finds duplications and 5 on recoverable errors, so its exit code is not read:
the parseable report is the success signal (design T1).

Tunables arrive as environment variables the calling skill exports from the
resolved configuration:

  CODE_METRICS_DUP_MIN_TOKENS  --minimum-tokens          (default 50)
  CODE_METRICS_DUP_MIN_LINES   applied here after parsing (default 5): CPD has
                               no minimum-lines option, so groups shorter than
                               the minimum are dropped by this adapter
  CODE_METRICS_DUP_IGNORE      not passed: CPD's `--exclude` takes file paths,
                               not globs, so ignore patterns stay a jscpd
                               capability and are reported as unused here

CPD covers no Bash or shell language (PMD's CPD-capable language list read
2026-09-05), so the bash lane exits 3 with that reason rather than guessing.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ElementTree

MIN_PYTHON = (3, 9)
NAME = "cpd"
DEFAULT_MIN_TOKENS = "50"
DEFAULT_MIN_LINES = "5"
# lane -> the CPD language id (`--language`, whose default is java).
LANGUAGES = {
    "typescript": "ecmascript",
    "python": "python",
    "go": "go",
    "dotnet": "cs",
}


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


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _int_or_none(value: str | None) -> int | None:
    try:
        return int(value) if value is not None else None
    except ValueError:
        return None


def probe() -> int:
    exe = shutil.which("pmd")
    if not exe:
        print("pmd not on PATH", file=sys.stderr)
        return 1
    try:
        out = subprocess.run(
            [exe, "--version"], capture_output=True, text=True, check=False
        )
    except OSError as exc:
        print(f"pmd --version failed: {exc}", file=sys.stderr)
        return 1
    match = re.search(r"(\d+\.\d+(?:\.\d+)?)", out.stdout + out.stderr)
    print(match.group(1) if match else "unknown-version")
    return 0


def translate(raw: str, lane: str, min_lines: int) -> list[dict]:
    root = ElementTree.fromstring(raw)
    rows: list[dict] = []
    for element in root:
        if _local(element.tag) != "duplication":
            continue
        lines = _int_or_none(element.get("lines"))
        if lines is not None and lines < min_lines:
            continue
        instances = [
            {
                "file": _normalize(child.get("path", "")),
                "start_line": _int_or_none(child.get("line")),
                "end_line": _int_or_none(child.get("endline")),
            }
            for child in element
            if _local(child.tag) == "file"
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
                    "lines": lines,
                    "tokens": _int_or_none(element.get("tokens")),
                },
                "collector": NAME,
                "labels": ["token-based"],
            }
        )
    return rows


def collect(lane: str, measure: str, files: list[str]) -> int:
    if measure != "duplication":
        print(f"cpd.py: cannot collect {measure}", file=sys.stderr)
        return 2
    language = LANGUAGES.get(lane)
    if not language:
        print(
            f"cpd.py: PMD CPD has no CPD-capable language for the {lane} lane",
            file=sys.stderr,
        )
        return 3
    exe = shutil.which("pmd")
    if not exe:
        print("pmd not on PATH", file=sys.stderr)
        return 3
    min_lines = _int_or_none(os.environ.get("CODE_METRICS_DUP_MIN_LINES")) or int(
        DEFAULT_MIN_LINES
    )
    work = tempfile.mkdtemp(prefix="code-metrics-cpd-")
    try:
        listing = os.path.join(work, "file-list.txt")
        with open(listing, "w", encoding="utf-8") as handle:
            for path in files:
                handle.write(path + "\n")
        result = subprocess.run(
            [
                exe,
                "cpd",
                "--minimum-tokens",
                os.environ.get("CODE_METRICS_DUP_MIN_TOKENS") or DEFAULT_MIN_TOKENS,
                "--format",
                "xml",
                "--language",
                language,
                "--file-list",
                listing,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    finally:
        shutil.rmtree(work, ignore_errors=True)
    try:
        rows = translate(result.stdout, lane, min_lines)
    except (ElementTree.ParseError, ValueError, TypeError) as exc:
        print(
            f"cpd.py: unparsable CPD XML ({exc}); stderr: {result.stderr.strip()}",
            file=sys.stderr,
        )
        return 3
    for row in rows:
        print(json.dumps(row))
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        print(
            "usage: cpd.py probe|measures|collect <lane> <measure> <file>...|install_hint",
            file=sys.stderr,
        )
        return 2
    verb, rest = argv[0], argv[1:]
    if verb == "probe":
        return probe()
    if verb == "measures":
        for lane in sorted(LANGUAGES):
            print(f"{lane}/duplication")
        return 0
    if verb == "install_hint":
        print(
            "PMD CPD: https://pmd.github.io (download the PMD 7 distribution or `brew install pmd`; it needs a JVM); this plugin never installs it"
        )
        return 0
    if verb == "collect":
        if len(rest) < 2:
            print("usage: cpd.py collect <lane> <measure> <file>...", file=sys.stderr)
            return 2
        return collect(rest[0], rest[1], rest[2:])
    print(f"cpd.py: unknown verb {verb}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print("cpd.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
