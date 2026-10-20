#!/usr/bin/env python3
"""Standing gate: digest prose carries no pipeline vocabulary.

The other standing gates read fences only. This one reads the prose of every
digest section (Summary, Key claims, Implications, Candidate artifacts, Open
questions for interview, and any other H2) and fails on a fixed list of
built-in pipeline terms: "unit NN" and "SOURCES.md". Those name the run, not
the documented mechanism. Fence payloads are verbatim source quotes and are
skipped. The term list is built in; no consumer configuration is read.

Exit codes:
  0  all checks passed
  1  one or more named check failures
  2  unusable input
  3  internal gate bug

Stdlib only. Python 3.9+.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import List, Optional, Tuple

sys.dont_write_bytecode = True  # the plugin's own tree is not a cache
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from digest_fences import (  # noqa: E402
    ATX_H2,
    Failures,
    _is_fence_closer,
    _is_fence_opener,
    fail,
    read_text,
    run_gate,
    split_lines,
)

PROG = "check-prose-terms"

# (label shown in a failure, pattern). Case-insensitive; "unit" must be a word
# so "community 3" or "opportunity 2" do not match.
TERMS: Tuple[Tuple[str, "re.Pattern[str]"], ...] = (
    ("unit NN", re.compile(r"\bunit[ \t]+\d+\b", re.IGNORECASE)),
    ("SOURCES.md", re.compile(r"\bSOURCES\.md\b", re.IGNORECASE)),
)
PREAMBLE = "(before the first ## heading)"


def prose_lines(text: str):
    """Yield (line_number, section_title, line) for each line outside a fence."""
    section = PREAMBLE
    in_fence = False
    open_ticks = 0
    for idx, line in enumerate(split_lines(text), start=1):
        if in_fence:
            if _is_fence_closer(line, open_ticks):
                in_fence = False
            continue
        is_open, _indented, ticks = _is_fence_opener(line)
        if is_open:
            in_fence = True
            open_ticks = ticks
            continue
        heading = ATX_H2.match(line)
        if heading:
            section = heading.group(1)
        yield idx, section, line
    if in_fence:
        raise ValueError("a fence is never closed; the rest of the digest was not read")


def check_digest(path: str, failures: Failures) -> int:
    """Return the number of prose lines scanned on this digest."""
    text = read_text(path, PROG, "digest")
    scanned = 0
    try:
        lines = list(prose_lines(text))
    except ValueError as exc:
        failures.add(f"{path}: {exc}.")
        return 0
    if not any(line.strip() for _idx, _section, line in lines):
        failures.add(f"{path}: no prose outside fences; nothing to parse is not a PASS.")
        return 0
    for idx, section, line in lines:
        scanned += 1
        for label, pattern in TERMS:
            match = pattern.search(line)
            if match:
                failures.add(
                    f"{path}: line {idx}, section {section!r}: pipeline term "
                    f"{label!r} in prose ({match.group(0)!r}). Digest prose "
                    f"states the documented mechanism, not the run."
                )
    return scanned


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog=PROG,
        description="Gate digest prose sections against built-in pipeline terms.",
        epilog=(
            "exit codes: 0 all checks passed; 1 one or more named check "
            "failures; 2 unusable input; 3 internal gate bug"
        ),
    )
    parser.add_argument(
        "--digest",
        action="append",
        default=[],
        dest="digests",
        help="Digest file (repeatable; at least one required)",
    )
    args = parser.parse_args(argv)
    if not args.digests:
        fail(PROG, 2, "no --digest given; nothing to parse is not a PASS.")

    failures = Failures(PROG)
    scanned = 0
    for path in args.digests:
        scanned += check_digest(path, failures)

    if failures.items:
        failures.report_suppressed()
        print(
            f"{PROG}: FAILED -- {len(failures.items)} failure(s) across "
            f"{len(args.digests)} digest(s)."
        )
        return 1

    names = ", ".join(label for label, _ in TERMS)
    print(
        f"{PROG}: PASS -- exercised: {len(args.digests)} digest(s), "
        f"{scanned} prose line(s) outside fences scanned for the built-in "
        f"terms {names}. Fence payloads were not read, and org or "
        f"session-visible terms are not checked."
    )
    return 0


if __name__ == "__main__":
    run_gate(PROG, main)
