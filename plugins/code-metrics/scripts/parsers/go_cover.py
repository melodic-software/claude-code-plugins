#!/usr/bin/env python3
"""Parse a Go cover profile into the plugin's parser shape.

    parse(path) -> {file: {"lines": {}, "functions": None, "statements": {...}}}

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

A block is a statement count over a line range. It never says which of those
lines carry the statements, and the range routinely spans blank lines,
comments and braces that carry none. So a cover profile does not give per-line
executability, and this parser reports none: `lines` is always empty, and a Go
file's percentage comes from the statement counts below instead.

Expanding each block over its whole line range gets both numbers wrong. It
counts every line of the range as executable, and it weighs every statement by
the lines around it instead of by the block's own count. A real profile for

    func F(x int) int {
        if x > 0 {
            return 1
        }
        a := 1; b := 2; c := 3; d := 4; return a + b + c + d
    }

is three blocks, 7 statements, 2 of them hit, which `go tool cover -func`
reports as 28.6%. The expansion gives 5 executable lines with 4 hit, which the
join would turn into 80%, and the wrong percentage would feed CRAP as well.
The weights cannot ride on the line table either: that function holds 7
statements across 6 physical lines, so no map keyed by its line numbers can
carry 7 executable units at all.

`statements` is the profile's own weighting, and is where a Go percentage
comes from: `total` is every statement the profile lists for the file and
`hit` is the statements in blocks whose count is above zero, so `hit / total`
is exactly the ratio `go tool cover -func` prints. The join reads this key for
a file whose line table is empty and reports that ratio, leaving
`lines_executable` and `lines_hit` null, because they count lines and this
artifact counted something else. A block repeated across concatenated
profiles is folded on its
full `start.col,end.col` identity, keeping the larger count, so its statements
are weighed once.

A profile names no functions, so `functions` is always `None`. The file path is
the one the compiler saw, usually prefixed by the module path, so the join
resolves it against the scope rather than assuming it is repository-relative.

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
    r"^(?P<file>.+):(?P<start>\d+)\.(?P<start_col>\d+),"
    r"(?P<end>\d+)\.(?P<end_col>\d+) (?P<statements>\d+) (?P<count>\d+)$"
)


def _norm(path: str) -> str:
    path = path.strip().replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return path


def parse(path: str) -> dict[str, dict]:
    """Read `path` and return the per-file coverage mapping."""
    blocks: dict[str, dict[tuple[int, int, int, int], list[int]]] = {}
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
            key = (
                int(match.group("start")),
                int(match.group("start_col")),
                int(match.group("end")),
                int(match.group("end_col")),
            )
            statements = int(match.group("statements"))
            count = int(match.group("count"))
            per_file = blocks.setdefault(_norm(match.group("file")), {})
            record = per_file.get(key)
            if record is None:
                per_file[key] = [statements, count]
            else:
                record[0] = max(record[0], statements)
                record[1] = max(record[1], count)
    if not seen_mode:
        raise ValueError("not a Go cover profile (no `mode:` header)")
    return {
        name: {
            "lines": {},
            "functions": None,
            "statements": {
                "total": sum(weight for weight, _ in per_file.values()),
                "hit": sum(weight for weight, count in per_file.values() if count > 0),
            },
        }
        for name, per_file in blocks.items()
    }


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
