#!/usr/bin/env python3
"""Keep the regular text files from a scope listing, in one process.

The dispatcher resolves a scope as a list of paths and must drop what it
cannot measure: a path that is no longer a regular file, and a binary file
(a NUL byte in the first 8000 bytes, the sniff `grep -I` performs). Doing
that per file from bash costs several process spawns per path, which on a
whole repository is tens of seconds of pure scaffolding around a
measurement that takes a fraction of one; this script performs the same
check over the entire list in one process.

A file that exists but cannot be read is kept, not dropped: the collector
that later opens it reports the failure in its run row, where the reader
can see it, whereas a drop here would leave the file out of the scope with
nothing said.

Command line: `text-files.py --paths-from <file>` reads one path per line
(blank lines ignored) and prints the surviving paths one per line in the
same order. Exit 0 on success, 2 on a usage error or an unreadable list.
"""

from __future__ import annotations

import os
import sys

MIN_PYTHON = (3, 9)
SNIFF_BYTES = 8000

_USAGE = "usage: text-files.py --paths-from <file>"


def is_text_file(path: str) -> bool:
    """Whether `path` is a regular file that should stay in scope."""
    if not os.path.isfile(path):
        return False
    try:
        with open(path, "rb") as handle:
            head = handle.read(SNIFF_BYTES)
    except OSError:
        return True
    return b"\0" not in head


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[0] != "--paths-from":
        print(_USAGE, file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as handle:
            listed = [line.rstrip("\n") for line in handle if line.strip()]
    except OSError as exc:
        print(f"text-files.py: {exc}", file=sys.stderr)
        return 2
    for path in listed:
        if is_text_file(path):
            print(path)
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print("text-files.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
