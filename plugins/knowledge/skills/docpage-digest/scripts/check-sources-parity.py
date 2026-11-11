#!/usr/bin/env python3
"""Standing gate: SOURCES.md, the digest files and the source agree on headings and units.

Reads a slice directory holding source.md (or source.txt), SOURCES.md and digests/*.md.
Lists every heading in the source, both `#` lines and `<h1>`-`<h6>` tags carrying an
`id`, skipping fenced code. Then checks that:

- the `## Headings` table of SOURCES.md lists exactly those headings (line, level);
- the `## Digest map` ranges are contiguous, start at line 1, end at the last source
  line, and each unit starts at the pre-H2 introduction or at an H2 of either form;
- the digest map rows, the files in digests/ and the `## Status` rows name the same
  digest files.

SOURCES.md shape the gate reads (column 1 is what it parses):

  ## Headings        | line | level | text |      level is `2` or `H2`
  ## Digest map      | digest file | lines |      lines is `START-END`
  ## Status          - [ ] NN-slug.md ...

Any disagreement, a missing section or zero parsed rows is a failure naming the
mismatch, never a skip.

Exit codes:
  0  parity
  1  one or more named mismatches
  2  unusable input

Stdlib only. Python 3.9+.
"""

from __future__ import annotations

import argparse
import os
import re
import sys

sys.dont_write_bytecode = True  # the plugin's own tree is not a cache
sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, os.pardir, os.pardir, "lib")
)
from gates import headings  # noqa: E402  (the plugin's shared gate primitives)

PROG = "check-sources-parity"
EPILOG = """\
exit codes: 0 parity, 1 a named mismatch or nothing parsed, 2 unusable input"""

MD_HEADING = headings.atx_heading(trail=headings.TRAIL_CLOSING)
HTML_HEADING = headings.html_heading(line_start=True, require_id=True)
FENCE = headings.fence(indent=headings.INDENT_ANY)
DIGEST_NAME = re.compile(r"\b\d+-[A-Za-z0-9._-]+\.md\b")
RANGE = re.compile(r"^(\d+)\s*[-–]\s*(\d+)$")
LEVEL = re.compile(r"^H?([1-6])$", re.IGNORECASE)
SEPARATOR = re.compile(r"^\|[\s:|-]+\|$")
STATUS_ROW = re.compile(r"^\s*[-*]\s+\[[ xX]\]")


class Unusable(Exception):
    pass


def read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        raise Unusable(f"cannot read {path!r}: {exc}")


def source_lines(text):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def source_headings(lines):
    """(line, level, text) for every heading outside a fence."""
    found = []
    fence = None
    for number, line in enumerate(lines, 1):
        m = FENCE.match(line)
        if fence:
            if headings.closes_fence(m, fence):
                fence = None
            continue
        if m:
            fence = m.group(1)
            continue
        m = MD_HEADING.match(line)
        if m:
            found.append((number, len(m.group(1)), (m.group(2) or "").strip()))
            continue
        m = HTML_HEADING.match(line)
        if m:
            text = re.sub(r"<[^>]*>", "", m.group(2)).strip()
            found.append((number, int(m.group(1)), text))
    return found


def section(text, title):
    """Body lines under `## <title>`, or None when the section is absent."""
    body = None
    for line in text.split("\n"):
        m = re.match(r"^##[ \t]+(.*?)[ \t]*$", line)
        if m:
            if body is not None:
                break
            if m.group(1).lower() == title.lower():
                body = []
            continue
        if body is not None:
            body.append(line)
    return body


def table_rows(body):
    """Cell lists of each data row; the first table row is the header."""
    rows = []
    header_seen = False
    for line in body:
        line = line.strip()
        if not line.startswith("|"):
            continue
        if SEPARATOR.match(line):
            continue
        cells = [c.strip().strip("`").strip() for c in line.strip("|").split("|")]
        if not header_seen:
            header_seen = True
            continue
        rows.append(cells)
    return rows


def check(slice_dir):
    failures = []
    candidates = (os.path.join(slice_dir, name) for name in ("source.md", "source.txt"))
    source_path = next((path for path in candidates if os.path.isfile(path)), None)
    if source_path is None:
        raise Unusable(f"no source.md or source.txt in {slice_dir!r}")
    lines = source_lines(read(source_path))
    sources_text = read(os.path.join(slice_dir, "SOURCES.md"))
    digests_dir = os.path.join(slice_dir, "digests")
    try:
        on_disk = sorted(n for n in os.listdir(digests_dir) if n.endswith(".md"))
    except OSError as exc:
        raise Unusable(f"cannot list {digests_dir!r}: {exc}")

    found = source_headings(lines)
    h2_text = {n: t for n, lv, t in found if lv == 2}
    print(f"source: {len(lines)} line(s), {len(found)} heading(s) ({len(h2_text)} H2)")

    # Heading table.
    body = section(sources_text, "Headings")
    if body is None:
        failures.append("SOURCES.md has no '## Headings' section")
    else:
        listed = []
        for cells in table_rows(body):
            level = LEVEL.match(cells[1]) if len(cells) > 1 else None
            if not cells[0].isdigit() or not level:
                failures.append(f"SOURCES.md Headings row not parsed (want line, level): {'|'.join(cells)[:80]!r}")
                continue
            listed.append((int(cells[0]), int(level.group(1))))
        if not listed and not failures:
            failures.append("SOURCES.md Headings table parsed zero rows")
        truth = {(n, lv): t for n, lv, t in found}
        for key in sorted(set(truth) - set(listed)):
            failures.append(f"source heading missing from SOURCES.md Headings: line {key[0]} H{key[1]} {truth[key][:60]!r}")
        for key in sorted(set(listed) - set(truth)):
            failures.append(f"SOURCES.md Headings row is no source heading: line {key[0]} H{key[1]}")
        if len(listed) != len(set(listed)):
            failures.append("SOURCES.md Headings lists a heading more than once")

    # Digest map: contiguity, coverage, unit starts.
    mapped = []
    body = section(sources_text, "Digest map")
    if body is None:
        failures.append("SOURCES.md has no '## Digest map' section")
    else:
        ranges = []
        for cells in table_rows(body):
            name = DIGEST_NAME.search(cells[0])
            span = RANGE.match(cells[1]) if len(cells) > 1 else None
            if not name or not span:
                failures.append(f"SOURCES.md Digest map row not parsed (want file, START-END): {'|'.join(cells)[:80]!r}")
                continue
            mapped.append(name.group(0))
            ranges.append((int(span.group(1)), int(span.group(2)), name.group(0)))
        if not ranges:
            failures.append("SOURCES.md Digest map parsed zero rows")
        else:
            ranges.sort()
            expected = 1
            for start, end, name in ranges:
                if end < start:
                    failures.append(f"digest map range for {name} runs backwards: {start}-{end}")
                if start != expected:
                    kind = "gap" if start > expected else "overlap"
                    failures.append(f"digest map {kind} before {name}: expected line {expected}, got {start}")
                expected = max(expected, end + 1)
            if expected - 1 != len(lines):
                failures.append(f"digest map ends at line {expected - 1}, source has {len(lines)} line(s)")
            want = {1, *h2_text}
            got = {r[0] for r in ranges}
            for line in sorted(want - got):
                what = f"H2 {h2_text[line][:60]!r}" if line in h2_text else "the introduction"
                failures.append(f"no digest unit starts at line {line} ({what})")
            for line in sorted(got - want):
                failures.append(f"digest unit starts at line {line}, which is neither line 1 nor an H2")

    # Counts: map rows, digest files, status rows.
    status = []
    body = section(sources_text, "Status")
    if body is None:
        failures.append("SOURCES.md has no '## Status' section")
    else:
        for line in body:
            if not STATUS_ROW.match(line):
                continue
            name = DIGEST_NAME.search(line)
            if name:
                status.append(name.group(0))
            else:
                failures.append(f"SOURCES.md Status row names no digest file: {line.strip()[:80]!r}")
        if not status:
            failures.append("SOURCES.md Status parsed zero rows")
    print(f"digest map rows: {len(mapped)}, digest files: {len(on_disk)}, status rows: {len(status)}")
    sets = (("digest map", mapped), ("digests/", on_disk), ("Status", status))
    for label, names in sets:
        if len(names) != len(set(names)):
            failures.append(f"{label} names a digest file more than once")
    for (a_label, a), (b_label, b) in ((sets[0], sets[1]), (sets[0], sets[2])):
        for name in sorted(set(a) - set(b)):
            failures.append(f"{name} is in {a_label} but not in {b_label}")
        for name in sorted(set(b) - set(a)):
            failures.append(f"{name} is in {b_label} but not in {a_label}")
    return failures


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog=PROG,
        description="Check heading and digest-unit parity of a docpage-digest slice.",
        epilog=EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("slice_dir", help="work root holding source.md, SOURCES.md and digests/")
    args = ap.parse_args(argv)
    try:
        failures = check(args.slice_dir)
    except Unusable as exc:
        print(f"{PROG}: {exc}", file=sys.stderr)
        return 2
    for message in failures:
        print(f"FAIL {message}")
    print(f"{len(failures)} mismatch(es)" if failures else "PASS heading and unit parity")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
