#!/usr/bin/env python3
"""Generate the "Semantics at a glance" table in the config-cascade README.

    scripts/sync-config-cascade-semantics.py [README]           rewrite the generated block
    scripts/sync-config-cascade-semantics.py --check [README]   fail when the block is stale

SINGLE SOURCE OF TRUTH: the Implementers table in
`docs/conventions/config-cascade/README.md`. Its `Who wins` and `Merge form` columns
render into the block between the markers below, under `## Semantics at a glance`.
Never hand-edit the block: change the Implementers row and re-run this script. CI runs
`--check` and rejects drift, the same contract `scripts/sync-plugin-options-docs.py` uses.

Exit codes: 0 up to date or rewritten; 1 stale under `--check`, or an Implementers row
with an empty `Who wins` or `Merge form` cell, a duplicate surface, or a malformed row;
2 the markers or the Implementers table are missing, the README cannot be read, or
the arguments are wrong.
"""

from __future__ import annotations

import argparse
import difflib
import pathlib
import re
import sys

BEGIN = "<!-- BEGIN GENERATED: config-cascade semantics. Edit the Implementers table, then run scripts/sync-config-cascade-semantics.py -->"
END = "<!-- END GENERATED: config-cascade semantics -->"

README = (
    pathlib.Path(__file__).resolve().parent.parent
    / "docs/conventions/config-cascade/README.md"
)
COLUMNS = ("Surface", "Who wins", "Merge form")
UNESCAPED_PIPE = re.compile(r"(?<!\\)\|")
DELIMITER_CELL = re.compile(r":?-+:?")


class Fail(Exception):
    def __init__(self, code: int, *lines: str):
        super().__init__("\n".join(lines))
        self.code = code


def cells(line: str) -> list[str]:
    return [c.strip() for c in UNESCAPED_PIPE.split(line.strip()[1:-1])]


def implementers(text: str) -> list[list[str]]:
    """The Surface, Who wins and Merge form cells of every Implementers row, in order."""
    lines = text.splitlines()
    if "## Implementers" not in lines:
        raise Fail(2, "no '## Implementers' heading")
    table: list[str] = []
    for line in lines[lines.index("## Implementers") + 1 :]:
        if line.startswith("## "):
            break
        if line.startswith("|"):
            table.append(line)
        elif table:
            break
    if len(table) < 3:
        raise Fail(2, "no table under '## Implementers'")
    header = cells(table[0])
    missing = [c for c in COLUMNS if c not in header]
    if missing:
        raise Fail(2, f"Implementers table has no column: {', '.join(missing)}")
    if not all(DELIMITER_CELL.fullmatch(c) for c in cells(table[1])):
        raise Fail(2, "no delimiter row under the Implementers header")
    wanted = [header.index(c) for c in COLUMNS]

    rows: list[list[str]] = []
    problems: list[str] = []
    seen: set[str] = set()
    for line in table[2:]:
        row = cells(line)
        if len(row) != len(header):
            problems.append(
                f"row has {len(row)} cells, expected {len(header)}: {line[:60]}"
            )
            continue
        picked = [row[i] for i in wanted]
        surface = picked[0] or "(no surface)"
        problems += [
            f"{surface}: empty {name} cell"
            for name, cell in zip(COLUMNS, picked)
            if not cell
        ]
        if picked[0] in seen:
            problems.append(f"{surface}: duplicate surface")
        seen.add(picked[0])
        rows.append(picked)
    if problems:
        raise Fail(1, *problems)
    return rows


def render(rows: list[list[str]]) -> str:
    table = [f"| {' | '.join(COLUMNS)} |", "|---|---|---|"]
    table += [f"| {' | '.join(row)} |" for row in rows]
    return "\n".join([BEGIN, "", *table, "", END])


def splice(text: str, block: str) -> str:
    if (
        text.count(BEGIN) != 1
        or text.count(END) != 1
        or text.index(BEGIN) > text.index(END)
    ):
        raise Fail(2, "expected one BEGIN and one END generated marker, BEGIN first")
    return text[: text.index(BEGIN)] + block + text[text.index(END) + len(END) :]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("readme", nargs="?", type=pathlib.Path, default=README)
    parser.add_argument(
        "--check", action="store_true", help="fail with a diff when the block is stale"
    )
    args = parser.parse_args()

    try:
        current = args.readme.read_text(encoding="utf-8")
        rows = implementers(current)
        updated = splice(current, render(rows))
    except OSError as exc:
        print(f"cannot read {args.readme}: {exc}", file=sys.stderr)
        return 2
    except Fail as exc:
        print(f"{args.readme}: {exc}", file=sys.stderr)
        return exc.code

    if updated == current:
        print(f"config-cascade semantics: up to date ({len(rows)} surfaces)")
        return 0
    if args.check:
        sys.stderr.writelines(
            difflib.unified_diff(
                current.splitlines(keepends=True),
                updated.splitlines(keepends=True),
                f"{args.readme} (committed)",
                f"{args.readme} (generated)",
            )
        )
        print(
            "\nconfig-cascade semantics: stale. Run: python3 scripts/sync-config-cascade-semantics.py",
            file=sys.stderr,
        )
        return 1
    args.readme.write_text(updated, encoding="utf-8", newline="\n")
    print(f"config-cascade semantics: rewrote {args.readme} ({len(rows)} surfaces)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
