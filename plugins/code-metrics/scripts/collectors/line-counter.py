#!/usr/bin/env python3
"""The bundled line counter: the one collector with no prerequisite.

Adapter contract (design/contracts.md section 3), four verbs:

  probe                   prints "bundled" and exits 0; exits 1 when the
                          environment variable CODE_METRICS_DISABLE_BUNDLED is
                          set (a suite uses it to prove the all-lanes-unavailable
                          path).
  measures                prints the lane/measure pairs it produces.
  collect <lane> <measure> <file>...
                          prints one `measures[]` row per file as JSON lines.
  install_hint            prints one line.

It counts total and blank lines only. It is comment-agnostic by construction,
and every row says so in `labels`, because a comment-aware count needs a
language-aware tool (`scc`, which the ladder tries first).
"""

from __future__ import annotations

import json
import os
import sys

MIN_PYTHON = (3, 9)
NAME = "line-counter"


def count(path: str) -> dict[str, int]:
    total = 0
    blank = 0
    with open(path, "rb") as handle:
        for raw in handle:
            total += 1
            if not raw.strip():
                blank += 1
    return {
        "lines_total": total,
        "lines_blank": blank,
        "lines_non_blank": total - blank,
    }


def main(argv: list[str]) -> int:
    if not argv:
        print(
            "usage: line-counter.py probe|measures|collect <lane> <measure> <file>...|install_hint",
            file=sys.stderr,
        )
        return 2
    verb, rest = argv[0], argv[1:]
    if verb == "probe":
        if os.environ.get("CODE_METRICS_DISABLE_BUNDLED"):
            print("disabled by CODE_METRICS_DISABLE_BUNDLED", file=sys.stderr)
            return 1
        print("bundled")
        return 0
    if verb == "measures":
        print("*/file_lines")
        return 0
    if verb == "install_hint":
        print("bundled with the plugin; nothing to install")
        return 0
    if verb == "collect":
        if len(rest) < 2:
            print(
                "usage: line-counter.py collect <lane> <measure> <file>...",
                file=sys.stderr,
            )
            return 2
        lane, measure, files = rest[0], rest[1], rest[2:]
        if measure != "file_lines":
            print(f"line-counter.py: cannot collect {measure}", file=sys.stderr)
            return 2
        for path in files:
            try:
                values = count(path)
            except OSError as exc:
                print(f"line-counter.py: {path}: {exc}", file=sys.stderr)
                return 3
            row = {
                "file": path.replace("\\", "/"),
                "function": None,
                "lane": lane,
                "values": values,
                "collector": NAME,
                "labels": ["comment-agnostic"],
            }
            print(json.dumps(row))
        return 0
    print(f"line-counter.py: unknown verb {verb}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print(
            "line-counter.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
