#!/usr/bin/env python3
"""Parse a Go cover profile into the plugin's parser shape.

    parse(path) -> {file: {"lines": {line: hits}, "functions": None}}

Command line: `python3 go_cover.py <artifact>` prints that mapping as JSON.

The profile `go test -coverprofile` writes is a `mode:` header followed by one
line per basic block:

    mode: set
    example.com/mod/pkg/file.go:7.34,8.14 1 1
                                ^     ^   ^ ^
                                |     |   | execution count
                                |     |   statements in the block
                                |     end line and column
                                start line and column

A block covers its whole line range, so every line from the start line to the
end line takes the block's count; overlapping blocks (a closing brace shared
with the next block's start) keep the larger count rather than adding, so a
line is counted once. In `set` mode the count is 0 or 1; in `count` and
`atomic` mode it is the real number of executions.

A profile names no functions, only blocks, so `functions` is always `None` and
the coverage of a Go function is joined from its complexity collector's line
range over these exact statement lines. The file path is the one the compiler
saw, usually prefixed by the module path, so the join resolves it against the
scope rather than assuming it is repository-relative.

The format carries no comment syntax, so `../fixtures/coverage/go-cover.out`
cannot label itself: it is hand-written to this shape and is unverified
against a live run, a stamp `../../reference/collectors/audit-coverage.md`
records.
"""

from __future__ import annotations

import json
import re
import sys

MIN_PYTHON = (3, 9)
FORMAT = "go_cover"
BLOCK = re.compile(
    r"^(?P<file>.+):(?P<start>\d+)\.\d+,(?P<end>\d+)\.\d+ (?P<statements>\d+) (?P<count>\d+)$"
)


def _norm(path: str) -> str:
    path = path.strip().replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return path


def parse(path: str) -> dict[str, dict]:
    """Read `path` and return the per-file coverage mapping."""
    files: dict[str, dict] = {}
    seen_mode = False
    with open(path, encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            line = raw.strip()
            if not line:
                continue
            if not seen_mode and line.startswith("mode:"):
                seen_mode = True
                continue
            match = BLOCK.match(line)
            if not match:
                continue
            section = files.setdefault(
                _norm(match.group("file")), {"lines": {}, "functions": None}
            )
            count = int(match.group("count"))
            start, end = int(match.group("start")), int(match.group("end"))
            if end < start:
                start, end = end, start
            for number in range(start, end + 1):
                section["lines"][number] = max(section["lines"].get(number, 0), count)
    if not seen_mode:
        raise ValueError("not a Go cover profile (no `mode:` header)")
    return files


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: go_cover.py <artifact>", file=sys.stderr)
        return 2
    print(json.dumps(parse(argv[0]), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print("go_cover.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, ValueError) as exc:
        print(f"go_cover.py: {exc}", file=sys.stderr)
        sys.exit(2)
