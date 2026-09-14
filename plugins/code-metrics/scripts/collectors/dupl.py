#!/usr/bin/env python3
"""Adapter for `dupl`, the Go-only suffix-tree clone detector (mibk/dupl).

Adapter contract (design/contracts.md section 3): `probe`, `measures`,
`collect <lane> <measure> <file>...`, `install_hint`.

`dupl` is the second rung of `go/duplication` on the collector ladder, behind
`jscpd`. It parses Go only, so every other lane exits 3 with that reason.

Output shape, read from mibk/dupl's text printer (printer/text.go, 2026-09-05)
and unverified against a live run: the default text printer writes one
`found <n> clones:` line per clone group, then one `  <file>:<start>,<end>`
line per instance, then a `Found total <n> clone groups.` footer. The text
printer is parsed rather than `-plumbing`, whose
`<file>:<a>-<b>: duplicate of <file>:<c>-<d>` lines are pairwise and lose a
group of three or more copies. Any line that matches neither shape is ignored.

`dupl` reports no token count, so `values.tokens` is null, never zero, and its
`-t` threshold is a token count with no line equivalent. Tunables arrive as
environment variables the calling skill exports from the resolved
configuration:

  CODE_METRICS_DUP_MIN_TOKENS  dupl -t                    (default 50)
  CODE_METRICS_DUP_MIN_LINES   applied here after parsing (default 5): dupl has
                               no minimum-lines option, so groups shorter than
                               the minimum are dropped by this adapter
  CODE_METRICS_DUP_IGNORE      not passed: dupl has no ignore-glob option (only
                               `-vendor`), so ignore patterns stay a jscpd
                               capability and are reported as unused here

`dupl` exits non-zero on its own reporting paths, so its exit code is not read:
the parseable report is the success signal (design T1). It also ships no
version flag (its flags are `-files`, `-html`, `-plumbing`, `-t`/`-threshold`,
`-vendor`, `-v`/`-verbose`, read 2026-09-05), so `probe` resolves the binary on
PATH and reports `unknown-version` rather than scraping a digit out of a usage
message; running the bare command instead would scan the working directory.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

from adapter_paths import dispatch, int_or_none, relative_to_cwd, require_python

NAME = "dupl"
LANE = "go"
DEFAULT_MIN_TOKENS = "50"
DEFAULT_MIN_LINES = "5"
GROUP_RE = re.compile(r"^found\s+\d+\s+clones:")
INSTANCE_RE = re.compile(r"^\s+(?P<file>.+):(?P<start>\d+),(?P<end>\d+)\s*$")


def probe() -> int:
    if not shutil.which(NAME):
        print("dupl not on PATH", file=sys.stderr)
        return 1
    print("unknown-version")
    return 0


def _row(instances: list[dict], lane: str) -> dict:
    first = instances[0]
    lines = None
    if first["start_line"] is not None and first["end_line"] is not None:
        lines = first["end_line"] - first["start_line"] + 1
    return {
        "file": None,
        "function": None,
        "lane": lane,
        "instances": instances,
        "values": {"lines": lines, "tokens": None},
        "collector": NAME,
        "labels": ["suffix-tree", "no token count reported"],
    }


def translate(raw: str, lane: str, min_lines: int) -> list[dict]:
    rows: list[dict] = []
    instances: list[dict] = []

    def close() -> None:
        if len(instances) < 2:
            return
        row = _row(list(instances), lane)
        lines = row["values"]["lines"]
        if lines is None or lines >= min_lines:
            rows.append(row)

    for line in raw.splitlines():
        if GROUP_RE.match(line):
            close()
            instances = []
            continue
        match = INSTANCE_RE.match(line)
        if match:
            instances.append(
                {
                    "file": relative_to_cwd(match.group("file")),
                    "start_line": int_or_none(match.group("start")),
                    "end_line": int_or_none(match.group("end")),
                }
            )
    close()
    return rows


def collect(lane: str, measure: str, files: list[str]) -> int:
    if measure != "duplication":
        print(f"dupl.py: cannot collect {measure}", file=sys.stderr)
        return 2
    if lane != LANE:
        print(f"dupl.py: dupl parses Go only, not the {lane} lane", file=sys.stderr)
        return 3
    exe = shutil.which(NAME)
    if not exe:
        print("dupl not on PATH", file=sys.stderr)
        return 3
    min_lines = int_or_none(os.environ.get("CODE_METRICS_DUP_MIN_LINES")) or int(
        DEFAULT_MIN_LINES
    )
    result = subprocess.run(
        [
            exe,
            "-t",
            os.environ.get("CODE_METRICS_DUP_MIN_TOKENS") or DEFAULT_MIN_TOKENS,
            *files,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    rows = translate(result.stdout, lane, min_lines)
    if not rows and "clone" not in result.stdout:
        print(
            f"dupl.py: no parseable clone report; stderr: {result.stderr.strip()}",
            file=sys.stderr,
        )
        return 3
    for row in rows:
        print(json.dumps(row))
    return 0


def measures() -> None:
    print(f"{LANE}/duplication")


INSTALL_HINT = "dupl: https://github.com/mibk/dupl (go install github.com/mibk/dupl@latest); this plugin never installs it"


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
