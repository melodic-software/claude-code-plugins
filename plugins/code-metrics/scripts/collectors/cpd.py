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
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ElementTree

from adapter_paths import (
    dispatch,
    int_or_none,
    relative_to_cwd,
    require_python,
    version_or_unknown,
    version_output,
)

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


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def probe() -> int:
    exe = shutil.which("pmd")
    if not exe:
        print("pmd not on PATH", file=sys.stderr)
        return 1
    output = version_output(exe, "pmd")
    if output is None:
        return 1
    print(version_or_unknown(output))
    return 0


def translate(raw: str, lane: str, min_lines: int) -> list[dict]:
    root = ElementTree.fromstring(raw)
    rows: list[dict] = []
    for element in root:
        if _local(element.tag) != "duplication":
            continue
        lines = int_or_none(element.get("lines"))
        if lines is not None and lines < min_lines:
            continue
        instances = [
            {
                "file": relative_to_cwd(child.get("path", "")),
                "start_line": int_or_none(child.get("line")),
                "end_line": int_or_none(child.get("endline")),
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
                    "tokens": int_or_none(element.get("tokens")),
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
    min_lines = int_or_none(os.environ.get("CODE_METRICS_DUP_MIN_LINES")) or int(
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


def measures() -> None:
    for lane in sorted(LANGUAGES):
        print(f"{lane}/duplication")


INSTALL_HINT = "PMD CPD: https://pmd.github.io (download the PMD 7 distribution or `brew install pmd`; it needs a JVM); this plugin never installs it"


def main(argv: list[str]) -> int:
    return dispatch(
        NAME,
        argv,
        probe=probe,
        measures=measures,
        install_hint=INSTALL_HINT,
        collect=collect,
    )


if __name__ == "__main__":
    require_python(f"{NAME}.py")
    sys.exit(main(sys.argv[1:]))
