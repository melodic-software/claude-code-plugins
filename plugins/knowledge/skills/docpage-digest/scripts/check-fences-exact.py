#!/usr/bin/env python3
"""Standing gate: Key-claims fences are exact source bytes.

Parses bold ``**CN.**`` labels under a Key claims heading and diffs each
following column-0 fence payload against the immutable source. Payloads are
NOT stripped — a per-line ``.strip()`` is how indented-fence corruption and a
load-bearing trailing space earned a clean quote-gate result.

A clean run prints exactly what it exercised. Zero parsed claims is a failure,
never PASS. Unrecognised input is exit 2.

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
import sys
from typing import List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from digest_fences import (  # noqa: E402
    Failures,
    MIN_PYTHON,
    extract_fences,
    fail,
    find_section,
    parse_claims,
    payload_in_source,
    read_text,
)

PROG = "check-fences-exact"


def check_digest(path: str, source: str, failures: Failures) -> int:
    """Return the number of claims fully exercised on this digest."""
    text = read_text(path, PROG, "digest")
    found = find_section(text, "Key claims")
    if found is None:
        failures.add(
            f"{path}: no '## Key claims' heading; this gate parses that "
            f"section only and will not PASS over an unparsed digest.")
        return 0
    _title, body, heading_line = found
    try:
        claims = parse_claims(body, start_line=heading_line + 1)
    except ValueError as exc:
        failures.add(f"{path}: {exc}")
        return 0
    if not claims:
        failures.add(
            f"{path}: parsed ZERO claims under Key claims. A clean result "
            f"over nothing parsed is the quote-gate defect this gate exists "
            f"to refuse.")
        return 0

    seen = {}
    exercised = 0
    for claim in claims:
        label = f"{path}: C{claim.number} (line {claim.label_line})"
        if claim.number in seen:
            failures.add(f"{label}: duplicate **C{claim.number}.** "
                         f"(first at line {seen[claim.number]}).")
            continue
        seen[claim.number] = claim.label_line
        if claim.unfenced_blockquote:
            failures.add(
                f"{label}: quote is a blockquote, not a fence. The "
                f"markdownlint PostToolUse hook rewrites list markers and "
                f"renumbers lists inside blockquoted verbatim quotes.")
            continue
        if claim.unfenced_inline_code:
            failures.add(
                f"{label}: quote is an inline code span, not a fence. A "
                f"bare code span cannot hold a trailing space through the "
                f"hook.")
            continue
        if claim.fence is None:
            failures.add(
                f"{label}: no fenced container follows the label. Every "
                f"verbatim quote is a column-0 fence under **CN.**.")
            continue
        if claim.fence.indented:
            failures.add(
                f"{label}: fence opener at line {claim.fence.start_line} is "
                f"indented. Indented-fence corruption is a defect; this gate "
                f"does not strip indent to make it pass.")
            continue
        if claim.fence.payload == "":
            failures.add(
                f"{label}: fence payload is empty. An unfinished "
                f"placeholder is not a quote.")
            continue
        if not payload_in_source(claim.fence.payload, source):
            shown = claim.fence.payload.replace("\n", "\\n")
            if len(shown) > 80:
                shown = shown[:80] + "…"
            failures.add(
                f"{label}: fence payload is not an exact contiguous "
                f"substring of the source (no strip applied). Payload "
                f"starts {shown!r}.")
            continue
        exercised += 1

    try:
        section_fences = extract_fences(body, start_line=heading_line + 1)
    except ValueError as exc:
        failures.add(f"{path}: {exc}")
        return exercised
    claimed_starts = {c.fence.start_line for c in claims if c.fence}
    for fence in section_fences:
        if fence.start_line not in claimed_starts:
            failures.add(
                f"{path}: unlabelled fence at line {fence.start_line} under "
                f"Key claims; this gate only attests **CN.**-labelled "
                f"fences, so an unlabelled one is unparsed surface.")

    return exercised


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog=PROG,
        description="Gate Key-claims fence payloads against the source, "
                    "without stripping.")
    parser.add_argument("--source", required=True,
                        help="Immutable source.md / source.txt")
    parser.add_argument("--digest", action="append", default=[],
                        dest="digests",
                        help="Digest file (repeatable)")
    args = parser.parse_args(argv)
    if not args.digests:
        fail(PROG, 2, "no --digest given; nothing to parse is not a PASS.")

    source = read_text(args.source, PROG, "source")
    failures = Failures(PROG)
    exercised = 0
    for path in args.digests:
        exercised += check_digest(path, source, failures)

    if failures.items:
        print(f"{PROG}: FAILED -- {len(failures.items)} failure(s) across "
              f"{len(args.digests)} digest(s); {exercised} claim fence(s) "
              f"matched the source exactly.")
        return 1

    print(
        f"{PROG}: PASS -- exercised: source {args.source!r}, "
        f"{len(args.digests)} digest(s), {exercised} **CN.** fence "
        f"payload(s) compared as exact contiguous source substrings with "
        f"NO per-line strip (trailing spaces and indent preserved). "
        f"Checked: Key claims heading present, ≥1 labelled claim, column-0 "
        f"fence per label, no unlabelled fences, no blockquote/inline-code "
        f"substitutes. Nothing outside Key claims / **CN.** / fence "
        f"payloads was checked.")
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        sys.stderr.write(
            f"{PROG}: ERROR: Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]}+ "
            f"required.\n")
        sys.exit(2)
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:
        sys.stderr.write(
            f"{PROG}: ERROR: internal failure {type(exc).__name__}: {exc}. "
            f"This is a gate bug; the run is NOT clean.\n")
        sys.exit(3)
