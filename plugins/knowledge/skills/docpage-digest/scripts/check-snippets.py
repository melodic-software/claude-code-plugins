#!/usr/bin/env python3
"""Standing gate: Prompt-snippets fences are exact source bytes.

Parses the Prompt snippets section — the section the campaign quote gate
never walked, so five snippets fabricated from recall shipped under
"682/682 CLEAN". Each column-0 fence payload must be an exact contiguous
substring of the source. Payloads are NOT stripped.

A missing section, or a section with unparsed non-empty content and zero
fences, is a failure — never PASS. A recognised none-marker is a clean
zero-snippet run and is named as such.

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
    is_none_section,
    payload_in_source,
    preview_payload,
    read_text,
)

PROG = "check-snippets"


def check_digest(path: str, source: str, failures: Failures) -> int:
    """Return the number of snippet fences fully exercised on this digest."""
    text = read_text(path, PROG, "digest")
    found = find_section(text, "Prompt snippets")
    if found is None:
        failures.add(
            f"{path}: no '## Prompt snippets' heading. This is the section "
            f"no prior gate parsed; absence is a failure, not a skip."
        )
        return 0
    _title, body, heading_line = found
    if is_none_section(body):
        return 0
    if not body.strip():
        failures.add(
            f"{path}: Prompt snippets body is blank. A recognised "
            f"none-marker is the only legal empty form; silence is not "
            f"an assertion."
        )
        return 0
    try:
        fences = extract_fences(body, start_line=heading_line + 1)
    except ValueError as exc:
        failures.add(f"{path}: {exc}")
        return 0
    if not fences:
        failures.add(
            f"{path}: Prompt snippets has non-empty content but parsed "
            f"ZERO fences. Unparsed section content is the attack surface "
            f"(fabricated-from-recall snippets shipped here). Use a "
            f"column-0 fence or a recognised none-marker."
        )
        return 0

    exercised = 0
    for fence in fences:
        label = f"{path}: snippet fence at line {fence.start_line}"
        if fence.indented:
            failures.add(
                f"{label}: opener is indented. Indented-fence corruption "
                f"is a defect; this gate does not strip indent to pass."
            )
            continue
        if fence.payload == "":
            failures.add(
                f"{label}: payload is empty. An unfinished placeholder "
                f"is not a snippet."
            )
            continue
        if not payload_in_source(fence.payload, source):
            shown = preview_payload(fence.payload)
            failures.add(
                f"{label}: payload is not an exact contiguous substring "
                f"of the source (no strip applied). Payload starts "
                f"{shown!r}."
            )
            continue
        exercised += 1
    return exercised


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog=PROG, description="Gate Prompt-snippets fence payloads against the source."
    )
    parser.add_argument(
        "--source", required=True, help="Immutable source.md / source.txt"
    )
    parser.add_argument(
        "--digest",
        action="append",
        default=[],
        dest="digests",
        help="Digest file (repeatable)",
    )
    args = parser.parse_args(argv)
    if not args.digests:
        fail(PROG, 2, "no --digest given; nothing to parse is not a PASS.")

    source = read_text(args.source, PROG, "source")
    failures = Failures(PROG)
    exercised = 0
    for path in args.digests:
        exercised += check_digest(path, source, failures)

    if failures.items:
        print(
            f"{PROG}: FAILED -- {len(failures.items)} failure(s) across "
            f"{len(args.digests)} digest(s); {exercised} snippet fence(s) "
            f"matched the source exactly."
        )
        return 1

    print(
        f"{PROG}: PASS -- exercised: source {args.source!r}, "
        f"{len(args.digests)} digest(s), {exercised} Prompt-snippets fence "
        f"payload(s) compared as exact contiguous source substrings with "
        f"NO per-line strip. Checked: Prompt snippets heading present, "
        f"each fence column-0 and in-source (or a recognised none-marker). "
        f"Nothing outside Prompt snippets / fence payloads was checked."
    )
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        sys.stderr.write(
            f"{PROG}: ERROR: Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]}+ required.\n"
        )
        sys.exit(2)
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:
        sys.stderr.write(
            f"{PROG}: ERROR: internal failure {type(exc).__name__}: {exc}. "
            f"This is a gate bug; the run is NOT clean.\n"
        )
        sys.exit(3)
