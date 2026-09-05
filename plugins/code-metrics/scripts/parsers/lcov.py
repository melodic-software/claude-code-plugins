#!/usr/bin/env python3
"""Parse an lcov `.info` tracefile into the plugin's coverage-parser shape.

    parse(path) -> {file: {"lines": {line: hits}, "functions": [...] | None}}

Command line: `python3 lcov.py <artifact>` prints that mapping as JSON.

Records read (geninfo(1), verified 2026-09-05):

  SF:<path>                 section header; the path may be absolute
  DA:<line>,<count>[,<md5>] line data; the third checksum field is optional
  FN:<start>[,<end>],<name> function record, lcov 1.x (an end line only in
                            some producers)
  FNDA:<count>,<name>       function execution count, lcov 1.x
  FNL:<index>,<start>[,<end>]   function leader, lcov 2.2 and later
  FNA:<index>,<count>,<name>    function alias, lcov 2.2 and later
  end_of_record             section terminator

Every other record is skipped, so an MC/DC tracefile parses without special
handling and a `BRDA` whose `taken` field is the literal `-` is never coerced
to a count. The skipped set: TN, VER, FNF, FNH, BRDA, BRF, BRH, LF, LH, and
the three MC/DC records MCDC, MCF and MCH.  # spellchecker:disable-line

Why both function forms: LCOV 2.2 replaced the `FN`/`FNDA` name pairing with
the index-based `FNL`/`FNA` pair, so a parser written against the older shape
reports zero function coverage on a modern tracefile. Both are read here and
merged on the name together with the start line, because one file can declare
the same name at two lines; `FNL` is where a function end line can come from at
all. A `FNDA` record carries only a name, so where a name is declared more than
once the nth count belongs to the nth `FN` declaration of it.

The `.info` format has no comment syntax, so the fixtures under
`../fixtures/coverage/lcov-1x.info`, `lcov-2.2.info` and `lcov-absolute-sf.info`
cannot carry a label: they are hand-written to this record set and are
unverified against a live run. `../../reference/collectors/audit-coverage.md`
carries that stamp.

Paths are returned as the tracefile spells them, with backslashes folded to
forward slashes and a leading `./` removed; the join normalizes the rest,
because only the caller knows the repository root and the configured prefixes.
"""

from __future__ import annotations

import json
import sys
from typing import Any

MIN_PYTHON = (3, 9)
FORMAT = "lcov"


def _norm(path: str) -> str:
    path = path.strip().replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return path


def _int(text: str) -> int | None:
    try:
        return int(text.strip())
    except ValueError:
        return None


def _section() -> dict[str, Any]:
    return {"lines": {}, "functions": None}


def _finish(
    section: dict[str, Any],
    starts: dict[tuple, int | None],
    ends: dict[tuple, int | None],
    hits: dict[tuple, int],
    order: list[tuple],
) -> None:
    if not order:
        return
    functions = []
    for key in order:
        functions.append(
            {
                "name": key[0],
                "start_line": starts.get(key, key[1]),
                "end_line": ends.get(key),
                "hit": hits.get(key),
                "lines": None,
            }
        )
    # One tracefile can carry several `SF` blocks for the same source file (a
    # concatenation of per-suite runs). The `DA` counts already merge with
    # `max` into the shared section, so the function records must fold the
    # same way: replacing them would let a later block's `FNDA:0` erase an
    # earlier hit and report the function at 0 percent, at maximal CRAP, in a
    # file the line table shows as covered. The fold key is the name with the
    # start line, the same identity the accumulators carry, because one file
    # can hold two functions of the same name at different lines.
    existing = {(f["name"], f["start_line"]): f for f in section["functions"] or []}
    for function in functions:
        key = (function["name"], function["start_line"])
        previous = existing.get(key)
        if previous is None:
            existing[key] = function
            continue
        if previous["end_line"] is None:
            previous["end_line"] = function["end_line"]
        counts = [h for h in (previous["hit"], function["hit"]) if h is not None]
        previous["hit"] = max(counts) if counts else None
    folded = list(existing.values())
    folded.sort(key=lambda f: (f["start_line"] is None, f["start_line"] or 0))
    section["functions"] = folded


def parse(path: str) -> dict[str, dict]:
    """Read `path` and return the per-file coverage mapping."""
    files: dict[str, dict] = {}
    section: dict[str, Any] | None = None
    # Keyed by (name, start line): one `SF` section can declare two functions
    # of the same name at different lines (two `render` methods in two
    # classes). Keyed by name alone they collapse into one record, and the
    # survivor wears the other's execution count.
    starts: dict[tuple, int | None] = {}
    ends: dict[tuple, int | None] = {}
    hits: dict[tuple, int] = {}
    order: list[tuple] = []
    leaders: dict[str, list] = {}
    # `FN` declarations per name, in file order, and how many `FNDA` counts
    # each name has consumed. `FNDA` carries only the name, so the nth count
    # for a name belongs to the nth declaration of it.
    declared: dict[str, list[tuple]] = {}
    counted: dict[str, int] = {}
    with open(path, encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            line = raw.strip()
            if not line:
                continue
            if line == "end_of_record":
                if section is not None:
                    _finish(section, starts, ends, hits, order)
                section = None
                continue
            record, _, rest = line.partition(":")
            if record == "SF":
                if section is not None:
                    _finish(section, starts, ends, hits, order)
                path_key = _norm(rest)
                section = files.setdefault(path_key, _section())
                starts, ends, hits, order, leaders = {}, {}, {}, [], {}
                declared, counted = {}, {}
                continue
            if section is None:
                continue
            if record == "DA":
                fields = rest.split(",")
                number, count = (
                    (_int(fields[0]), _int(fields[1]))
                    if len(fields) >= 2
                    else (None, None)
                )
                if number is not None and count is not None:
                    previous = section["lines"].get(number, 0)
                    section["lines"][number] = max(previous, count)
            elif record == "FN":
                fields = rest.split(",")
                if len(fields) < 2:
                    continue
                start = _int(fields[0])
                end = _int(fields[1]) if len(fields) >= 3 else None
                name = ",".join(fields[2:]) if end is not None else ",".join(fields[1:])
                name = name.strip()
                if not name:
                    continue
                key = (name, start)
                if key not in order:
                    order.append(key)
                    declared.setdefault(name, []).append(key)
                starts[key] = start
                ends[key] = end
            elif record == "FNDA":
                count, _, name = rest.partition(",")
                name = name.strip()
                value = _int(count)
                if name and value is not None:
                    seen = declared.get(name) or []
                    if seen:
                        index = min(counted.get(name, 0), len(seen) - 1)
                        counted[name] = counted.get(name, 0) + 1
                        key = seen[index]
                    else:
                        key = (name, None)
                        if key not in order:
                            order.append(key)
                            declared.setdefault(name, []).append(key)
                    hits[key] = max(hits.get(key, 0), value)
            elif record == "FNL":
                fields = rest.split(",")
                if len(fields) < 2:
                    continue
                index = fields[0].strip()
                leaders[index] = [
                    _int(fields[1]),
                    _int(fields[2]) if len(fields) >= 3 else None,
                ]
            elif record == "FNA":
                fields = rest.split(",", 2)
                if len(fields) < 3:
                    continue
                index, count, name = (
                    fields[0].strip(),
                    _int(fields[1]),
                    fields[2].strip(),
                )
                if not name:
                    continue
                leader = leaders.get(index)
                # `FNA` carries its own count, so the leader it points at is
                # the start line: no positional pairing is needed here.
                key = (name, leader[0] if leader else None)
                if key not in order:
                    order.append(key)
                    declared.setdefault(name, []).append(key)
                if count is not None:
                    hits[key] = max(hits.get(key, 0), count)
                if leader:
                    starts[key] = leader[0]
                    ends[key] = leader[1]
    if section is not None:
        _finish(section, starts, ends, hits, order)
    return files


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: lcov.py <artifact>", file=sys.stderr)
        return 2
    print(json.dumps(parse(argv[0]), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print("lcov.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    try:
        sys.exit(main(sys.argv[1:]))
    except OSError as exc:
        print(f"lcov.py: {exc}", file=sys.stderr)
        sys.exit(2)
