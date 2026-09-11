#!/usr/bin/env python3
"""Normalize a scope listing to the regular text files it names.

    scope-filter.py --paths-from <file>

Reads one path per line and prints the paths that survive, one per line, in
first-seen order:

- a carriage return is stripped, a backslash becomes a forward slash, and a
  leading `./` is dropped, so the same file listed two ways is one entry;
- a repeated path is printed once;
- a path that is not a regular file (a directory, a dangling symlink, a path
  git listed that was deleted from the working tree) is dropped;
- a file whose first 8000 bytes hold a NUL byte is dropped as binary, the same
  sniff `grep -I` performs without depending on GNU grep.

The dispatcher used to do this as a shell loop with two subprocesses per file,
which on a tree of a few thousand files was most of a whole-tree run. One
process over the list is the same decision at a fixed cost.

Exit 0 when the list was filtered, 2 on a usage error.
"""

from __future__ import annotations

import os
import sys

MIN_PYTHON = (3, 9)
SNIFF_BYTES = 8000


def normalize(path: str) -> str:
    path = path.rstrip("\r").replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return path


def is_text_file(path: str) -> bool:
    if not os.path.isfile(path):
        return False
    try:
        with open(path, "rb") as handle:
            return b"\0" not in handle.read(SNIFF_BYTES)
    except OSError as exc:
        # A file that exists but cannot be read is dropped so one locked file
        # does not turn a whole lane unavailable, and named on stderr so it
        # does not vanish from the scope with nothing said.
        print(
            f"scope-filter.py: dropped, cannot read: {path} ({exc.strerror})",
            file=sys.stderr,
        )
        return False


def filter_paths(lines: list[str]) -> list[str]:
    seen: set[str] = set()
    kept: list[str] = []
    for raw in lines:
        path = normalize(raw)
        if not path or path in seen:
            continue
        seen.add(path)
        if is_text_file(path):
            kept.append(path)
    return kept


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[0] != "--paths-from":
        print("usage: scope-filter.py --paths-from <file>", file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8", errors="surrogateescape") as handle:
            lines = handle.read().split("\n")
    except OSError as exc:
        print(f"scope-filter.py: {exc}", file=sys.stderr)
        return 2
    out = sys.stdout
    for path in filter_paths(lines):
        out.write(path + "\n")
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print(
            "scope-filter.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
