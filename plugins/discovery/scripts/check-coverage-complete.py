#!/usr/bin/env python3
"""Deterministic gate for a /discovery:research coverage ledger.

Python twin of check-coverage-complete.sh — same CLI, same exit codes, same
greppable summary. Use when the Bash tool cannot run the .sh form (for example a
sibling PreToolUse belt) but python3 is reachable from an open lane.

Exit 0 = every row's Done box is marked (status=complete)
Exit 1 = at least one row is unmarked (status=incomplete)
Exit 2 = the ledger cannot be graded — missing, empty, no table, no rows, no
         Done column, a short row, or a Done cell that is neither marked nor
         unmarked — plus usage errors. FAIL CLOSED: a ledger this gate cannot
         read is never reported as complete.

Usage:
  python3 check-coverage-complete.py <ledger-path>
  python3 check-coverage-complete.py --help
  ./check-coverage-complete.py <ledger-path>
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REQUIRED = ("#", "corpus item", "depth criterion", "done")
MARKED = re.compile(r"^\[[xX]\]\s*$")
UNMARKED = re.compile(r"^\[[ \t]*\]\s*$")
USAGE = """Deterministic gate for a /discovery:research coverage ledger.

Python twin of check-coverage-complete.sh — same CLI, same exit codes, same
greppable summary. Use when the Bash tool cannot run the .sh form (for example a
sibling PreToolUse belt) but python3 is reachable from an open lane.

Exit 0 = every row's Done box is marked (status=complete)
Exit 1 = at least one row is unmarked (status=incomplete)
Exit 2 = the ledger cannot be graded — missing, empty, no table, no rows, no
         Done column, a short row, or a Done cell that is neither marked nor
         unmarked — plus usage errors. FAIL CLOSED: a ledger this gate cannot
         read is never reported as complete.

Usage:
  python3 check-coverage-complete.py <ledger-path>
  python3 check-coverage-complete.py --help
  ./check-coverage-complete.py <ledger-path>

Ledger shape (the Done column is located by header name, not by position):

  | # | Corpus item | Depth criterion | Done |
  |---|-------------|-----------------|------|
  | 1 | <item>      | <criterion>     | [x]  |

Output (stdout, greppable): rows=<n> unmarked=<m> status=<complete|incomplete>
On status=incomplete each unmarked row is named on stderr.
"""


def cells(line: str) -> list[str]:
    # A backslash-escaped pipe is CONTENT, not a delimiter.
    protected = line.replace("\\|", "\x1e")
    raw = protected.split("|")
    out: list[str] = []
    for i, part in enumerate(raw):
        text = part.strip()
        if i == 0 and text == "":
            continue
        if i == len(raw) - 1 and text == "":
            continue
        out.append(text.replace("\x1e", "|"))
    return out


def is_separator(line: str) -> bool:
    probe = re.sub(r"[ \t|:\-]", "", line)
    return probe == ""


def grade(ledger_path: Path) -> int:
    if not ledger_path.is_file():
        print(f"error: ledger not found: {ledger_path}", file=sys.stderr)
        return 2
    text = ledger_path.read_text(encoding="utf-8")
    if text == "":
        print(f"error: ledger is empty: {ledger_path}", file=sys.stderr)
        return 2

    header_seen = False
    header_cols = 0
    header_name: dict[int, str] = {}
    done_col = 0
    rows = 0
    unmarked = 0

    for raw_line in text.splitlines():
        line = raw_line
        if not line.lstrip().startswith("|"):
            continue
        if is_separator(line):
            continue
        row_cells = cells(line)
        if not row_cells:
            continue

        if not header_seen:
            seen_head: dict[str, int] = {}
            for i, cell in enumerate(row_cells, start=1):
                header_name[i] = cell
                h = cell.lower()
                seen_head[h] = seen_head.get(h, 0) + 1
                if h == "done":
                    done_col = i
            ok = all(seen_head.get(req, 0) == 1 for req in REQUIRED)
            if not ok:
                done_col = 0
                continue
            header_cols = len(row_cells)
            header_seen = True
            continue

        if len(row_cells) != header_cols:
            print(
                f"error: row {rows + 1} has {len(row_cells)} column(s), "
                f"header has {header_cols}: {line}",
                file=sys.stderr,
            )
            return 2

        rows += 1
        for i in range(1, header_cols + 1):
            if i == done_col:
                continue
            if row_cells[i - 1] == "":
                print(
                    f"error: row {rows} has an empty {header_name[i]} cell — "
                    f"a marked row must say what covering it meant: {line}",
                    file=sys.stderr,
                )
                return 2

        box = row_cells[done_col - 1]
        if MARKED.match(box):
            continue
        if UNMARKED.match(box):
            unmarked += 1
            item = (
                row_cells[1]
                if header_cols >= 2 and done_col != 2
                else row_cells[0]
            )
            print(f"unmarked: row {rows} — {item}", file=sys.stderr)
            continue
        label = "<empty>" if box == "" else box
        print(f"error: row {rows} has an ungradeable Done cell: {label}", file=sys.stderr)
        return 2

    if not header_seen:
        print("error: no coverage table with a Done column found", file=sys.stderr)
        return 2
    if rows == 0:
        print("error: coverage table has a header but no rows", file=sys.stderr)
        return 2

    status = "incomplete" if unmarked else "complete"
    print(f"rows={rows} unmarked={unmarked} status={status}")
    return 1 if unmarked else 0


def main(argv: list[str]) -> int:
    ledger: str | None = None
    for arg in argv[1:]:
        if arg in ("--help", "-h"):
            print(USAGE, end="")
            return 0
        if arg.startswith("-"):
            print(f"error: unknown argument: {arg}", file=sys.stderr)
            return 2
        if ledger is not None:
            print(
                f"error: expected exactly one ledger path, got a second: {arg}",
                file=sys.stderr,
            )
            return 2
        ledger = arg

    if ledger is None:
        print("error: a ledger path is required", file=sys.stderr)
        return 2
    return grade(Path(ledger))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
