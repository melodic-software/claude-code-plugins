#!/usr/bin/env python3
"""Check F-labeled digest rows against source.html.

A row passes EXACT when its fence payload is a contiguous substring of the raw
source.html bytes. Otherwise it passes JOIN when every payload line equals one
text node or one attribute value of source.html (HTML entities decoded, no
whitespace forgiveness); a line that is only "..." or "…" is a declared
truncation and is counted. Anything else fails.

Stdlib only. Python 3.9+.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from html.parser import HTMLParser

LABEL = re.compile(r"^\*\*F(\d+)\.\*\*")
C_LABEL = re.compile(r"^\*\*C\d+\.\*\*")
ELLIPSIS = {"...", "…"}
EPILOG = """\
exit codes: 0 every F row passed, 1 a row failed or zero F rows were parsed,
2 usage error or unreadable file"""


class Pieces(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.pieces = set()

    def handle_data(self, data):
        self.pieces.add(data)

    def handle_starttag(self, tag, attrs):
        for _, value in attrs:
            if value:
                self.pieces.add(value)


def f_rows(text):
    lines = text.split("\n")
    rows = []
    for i, line in enumerate(lines):
        m = LABEL.match(line)
        if not m:
            continue
        j = i + 1
        while j < len(lines) and not lines[j].startswith("```"):
            if LABEL.match(lines[j]) or C_LABEL.match(lines[j]):
                break
            j += 1
        if j >= len(lines) or not lines[j].startswith("```"):
            rows.append((m.group(1), i + 1, None))
            continue
        k = j + 1
        body = []
        while k < len(lines) and not lines[k].startswith("```"):
            body.append(lines[k])
            k += 1
        rows.append((m.group(1), i + 1, "\n".join(body)))
    return rows


def read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        print(f"check-html-rows: cannot read {path!r}: {exc}", file=sys.stderr)
        sys.exit(2)


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="check-html-rows",
        description="Check **FN.**-labeled digest fence payloads against source.html.",
        epilog=EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("source", help="the page's raw source.html")
    ap.add_argument("digests", nargs="+", metavar="digest", help="digest markdown file(s)")
    args = ap.parse_args(argv)

    raw = read(args.source)
    texts = [(path, read(path)) for path in args.digests]
    parser = Pieces()
    parser.feed(raw)
    failures = total = 0
    for path, text in texts:
        for num, line, payload in f_rows(text):
            total += 1
            name = f"{os.path.basename(path)} F{num} (line {line})"
            if payload is None:
                print(f"FAIL {name}: no fence follows the label")
                failures += 1
            elif payload in raw:
                print(f"EXACT {name}")
            else:
                cuts = sum(ln in ELLIPSIS for ln in payload.split("\n"))
                missing = [
                    ln for ln in payload.split("\n")
                    if ln and ln not in ELLIPSIS and ln not in parser.pieces
                ]
                if missing:
                    print(f"FAIL {name}: {len(missing)} line(s) not a text node or attribute value, first {missing[0][:80]!r}")
                    failures += 1
                else:
                    print(f"JOIN {name}: {len(payload.splitlines())} line(s), each a text node or attribute value; {cuts} declared truncation line(s)")
    print(f"{total} F row(s) checked, {failures} failure(s)")
    return 1 if failures or total == 0 else 0


if __name__ == "__main__":
    sys.exit(main())
