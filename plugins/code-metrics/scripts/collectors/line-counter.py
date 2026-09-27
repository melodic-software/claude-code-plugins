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

from adapter_paths import dispatch, require_python

NAME = "line-counter"
INSTALL_HINT = "bundled with the plugin; nothing to install"


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


def probe() -> int:
    if os.environ.get("CODE_METRICS_DISABLE_BUNDLED"):
        print("disabled by CODE_METRICS_DISABLE_BUNDLED", file=sys.stderr)
        return 1
    print("bundled")
    return 0


def measures() -> None:
    print("*/file_lines")


def collect(lane: str, measure: str, files: list[str]) -> int:
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
