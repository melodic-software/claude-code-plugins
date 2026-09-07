#!/usr/bin/env python3
"""Bind the code-metrics config reference table to the bundled defaults file.

`plugins/code-metrics/scripts/config-defaults.json` is the single source of
truth the resolver reads at run time. `plugins/code-metrics/reference/config.md`
restates every key in a `## Keys` table with its default and its provenance.
The setup template is already pinned to the defaults leaf for leaf by
`plugins/code-metrics/skills/setup/scripts/test_setup_apply.py`; the reference
table was not pinned to anything, so it drifts the first time a key is added,
removed, renamed, or given a different default, and a stale default in a
reference reads exactly like a current one.

WHY VERIFY RATHER THAN GENERATE. Generating the table would need every column
to be derivable from the defaults file, and the third column is not: for 12 of
the table's 20 rows the "meaning and provenance" prose exists nowhere but the
document, and the 8 rows with a `thresholds[].provenance` string in the defaults
are reworded there for a reader rather than quoted. Generating would therefore
mean moving documentation prose into the JSON the resolver loads at run time.
The two columns that ARE derivable -- the key set and the default value -- are
pinned here instead, byte for byte against a canonical rendering, so the
mechanically checkable half cannot disagree while the prose half stays hand
written and readable. That is the shape the issue calls "verify" (#3841).

WHAT IS PINNED, exactly:

  * Every non-reserved leaf of the defaults file is documented by exactly one
    table row. A leaf documented by no row fails; a leaf documented by two
    rows fails, because then it is unclear which row states its default.
  * Every table row documents at least one defaults leaf, unless its default
    cell is the bare word `absent`, which is how the document marks a key that
    has no bundled default (`lanes.<lane>.collectors.<measure>`). A row that
    stops matching any leaf -- the shape of a key REMOVED from the defaults --
    fails and names the key.
  * Each row's default cell equals the canonical rendering of the value, which
    is exact: `20`, `null`, `[]`, `true`, and a string as itself, each inside a
    code span, with a `|` backslash-escaped (a raw pipe ends the cell even
    inside a code span) and the fence widened past any backtick run in the
    value. A value carrying a newline is NOT representable in a table cell and
    is reported as such rather than silently flattened.

Row ORDER is deliberately not pinned. The document groups keys for a reader and
the defaults file groups them for the resolver; requiring the two orders to
agree would fail a harmless reformat of either while preventing no drift.

Usage:

    scripts/check-code-metrics-config-reference.py
    scripts/check-code-metrics-config-reference.py --defaults FILE --doc FILE

Exit codes: 0 clean, 1 the two surfaces disagree, 2 the gate could not run
(fail closed: a missing file, unparseable JSON, or no table under `## Keys`).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# `from __future__ import annotations` is a SyntaxError below 3.7, before any
# runtime check here could run, so the sibling .test.sh parses this tuple as
# text to pick a qualifying interpreter BEFORE invoking this file.
MIN_PYTHON = (3, 7)

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DEFAULTS = (
    REPO_ROOT / "plugins" / "code-metrics" / "scripts" / "config-defaults.json"
)
DEFAULT_DOC = REPO_ROOT / "plugins" / "code-metrics" / "reference" / "config.md"

# Top-level defaults members that are not consumer configuration. The document
# says so itself, under "Reserved keys": `thresholds` and anything starting
# with `_` belong to the bundled defaults and the resolver's output.
RESERVED_PREFIX = "_"
RESERVED_KEYS = frozenset({"thresholds"})

# The heading whose first table is the key contract, and the literal a row uses
# for a documented key that the defaults file deliberately does not default.
SECTION_HEADING = "## Keys"
NO_DEFAULT = "absent"

# A `<name>` segment in a documented key stands for exactly one path segment,
# which is how one row documents `lanes.<lane>.enabled` for all five lanes.
WILDCARD = re.compile(r"^<[A-Za-z_][A-Za-z0-9_]*>$")

# A cell boundary is a pipe that is not backslash-escaped.
CELL_SPLIT = re.compile(r"(?<!\\)\|")

# A code span: a run of backticks, optional one-space padding, then the content.
CODE_SPAN = re.compile(r"^(?P<fence>`+)(?P<body>.*)(?P=fence)$", re.DOTALL)


class GateError(Exception):
    """The gate cannot run and must fail closed rather than clear the file."""


class Unrepresentable(Exception):
    """A default value that no markdown table cell can carry."""


def leaves(node, prefix: str = ""):
    """Yield (dotted path, value) for every non-mapping value in the tree.

    A list is a leaf, not a branch: the document and the resolver both treat
    `scope.exclude` as one closed value, never as indexed sub-keys.
    """
    if isinstance(node, dict):
        for key, value in node.items():
            yield from leaves(value, f"{prefix}{key}.")
    else:
        yield prefix[:-1], node


def default_leaves(defaults: dict) -> "dict[str, object]":
    """The consumer-configurable leaves, reserved members dropped at the root."""
    out = {}
    for key, value in defaults.items():
        if key in RESERVED_KEYS or key.startswith(RESERVED_PREFIX):
            continue
        for path, leaf in leaves(value, f"{key}."):
            out[path] = leaf
    return out


def render_default(value) -> str:
    """The exact cell text that documents `value`, code span included.

    A string renders as itself (the document writes `change`, not `"change"`);
    everything else renders as JSON, which gives `null`, `true`, `[]` and bare
    numbers. Then two markdown hazards are handled rather than hoped away:

      * a `|` ends the table cell even inside a code span, so it is escaped;
      * a backtick inside the value needs a longer fence than the longest run
        it contains, plus a space of padding when the value starts or ends
        with one, which is CommonMark's own rule for a code span.
    """
    text = value if isinstance(value, str) else json.dumps(value)
    if "\n" in text or "\r" in text:
        raise Unrepresentable(text)
    escaped = text.replace("|", "\\|")
    longest = max((len(run) for run in re.findall(r"`+", escaped)), default=0)
    fence = "`" * (longest + 1)
    pad = " " if escaped.startswith("`") or escaped.endswith("`") else ""
    return f"{fence}{pad}{escaped}{pad}{fence}"


def read_code_span(cell: str) -> "str | None":
    """The content of a code-span cell with `\\|` unescaped, or None."""
    match = CODE_SPAN.match(cell.strip())
    if match is None or not match.group("body"):
        return None
    body = match.group("body")
    if body.startswith(" ") and body.endswith(" ") and body.strip():
        body = body[1:-1]
    return body.replace("\\|", "|")


def split_row(line: str) -> "list[str]":
    """The cells of a markdown table row, outer pipes discarded."""
    cells = CELL_SPLIT.split(line.strip())
    if cells and not cells[0].strip():
        cells = cells[1:]
    if cells and not cells[-1].strip():
        cells = cells[:-1]
    return [cell.strip() for cell in cells]


def key_table(doc_text: str) -> "list[tuple[int, list[str]]]":
    """The first table under `## Keys`, as (1-based line number, cells) rows."""
    lines = doc_text.splitlines()
    start = None
    for index, line in enumerate(lines):
        if line.strip() == SECTION_HEADING:
            start = index + 1
            break
    if start is None:
        raise GateError(f"no {SECTION_HEADING!r} heading in the reference document")

    rows: "list[tuple[int, list[str]]]" = []
    seen_table = False
    for index in range(start, len(lines)):
        line = lines[index]
        if line.startswith("## "):
            break
        if not line.strip().startswith("|"):
            if seen_table:
                break
            continue
        seen_table = True
        cells = split_row(line)
        # The delimiter row (`|---|---|---|`) carries no content.
        if cells and all(re.fullmatch(r":?-{2,}:?", cell) for cell in cells):
            continue
        rows.append((index + 1, cells))

    if not rows:
        raise GateError(f"no table under {SECTION_HEADING!r} in the reference document")
    # Drop the header row, whose first cell names the column rather than a key.
    header = rows[0][1]
    if not header or read_code_span(header[0]) is not None:
        raise GateError(
            f"the first row under {SECTION_HEADING!r} is not a header row: {header!r}"
        )
    return rows[1:]


def matches(pattern: str, path: str) -> bool:
    """Does a documented key, wildcards included, name this defaults leaf?"""
    want = pattern.split(".")
    have = path.split(".")
    if len(want) != len(have):
        return False
    return all(WILDCARD.match(w) or w == h for w, h in zip(want, have))


def check(defaults: dict, doc_text: str, doc_name: str) -> "list[str]":
    """Every disagreement between the two surfaces, each naming its key."""
    problems: "list[str]" = []
    expected = default_leaves(defaults)
    rows = key_table(doc_text)

    documented: "dict[str, list[str]]" = {path: [] for path in expected}
    for lineno, cells in rows:
        if len(cells) < 2:
            problems.append(f"{doc_name}:{lineno}: table row has fewer than two cells")
            continue
        key = read_code_span(cells[0])
        if key is None:
            problems.append(
                f"{doc_name}:{lineno}: the key cell {cells[0]!r} is not a code span; "
                "every documented key is written as `a.b.c`"
            )
            continue
        cell = cells[1].strip()
        hits = [path for path in expected if matches(key, path)]
        for path in hits:
            documented[path].append(key)

        if not hits:
            if cell != NO_DEFAULT:
                problems.append(
                    f"{doc_name}:{lineno}: `{key}` is documented here but the defaults file "
                    "defines no such key. Remove the row, or write its default cell as the "
                    f"bare word `{NO_DEFAULT}` if the key deliberately has no bundled default."
                )
            continue
        if cell == NO_DEFAULT:
            problems.append(
                f"{doc_name}:{lineno}: `{key}` is documented as having no default, but the "
                f"defaults file now defines it ({', '.join(sorted(hits))}). "
                "State the default instead."
            )
            continue

        distinct = {json.dumps(expected[path], sort_keys=True) for path in hits}
        if len(distinct) > 1:
            problems.append(
                f"{doc_name}:{lineno}: `{key}` covers {', '.join(sorted(hits))}, which no "
                "longer share one default, so a single row cannot state it. Split the row."
            )
            continue
        try:
            want = render_default(expected[hits[0]])
        except Unrepresentable:
            problems.append(
                f"{doc_name}:{lineno}: the default for `{key}` contains a line break, which "
                "no markdown table cell can carry. Give the key a single-line default, or "
                "move the key out of this table."
            )
            continue
        if cell != want:
            problems.append(
                f"{doc_name}:{lineno}: `{key}` documents its default as {cell} but the "
                f"defaults file says {want}."
            )

    for path in sorted(expected):
        rows_for_path = documented[path]
        if not rows_for_path:
            problems.append(
                f"{doc_name}: the defaults file defines `{path}` and no row under "
                f"{SECTION_HEADING!r} documents it. Add a row for it."
            )
        elif len(rows_for_path) > 1:
            named = ", ".join(f"`{row}`" for row in rows_for_path)
            problems.append(
                f"{doc_name}: `{path}` is documented by more than one row ({named}), so "
                "which row states its default is ambiguous."
            )
    return problems


def main(argv: "list[str]") -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--defaults", type=Path, default=DEFAULT_DEFAULTS)
    parser.add_argument("--doc", type=Path, default=DEFAULT_DOC)
    args = parser.parse_args(argv)

    try:
        defaults_text = args.defaults.read_text(encoding="utf-8")
    except OSError as error:
        print(f"CANNOT RUN: {args.defaults}: {error}", file=sys.stderr)
        return 2
    try:
        doc_text = args.doc.read_text(encoding="utf-8")
    except OSError as error:
        print(f"CANNOT RUN: {args.doc}: {error}", file=sys.stderr)
        return 2
    try:
        defaults = json.loads(defaults_text)
    except json.JSONDecodeError as error:
        print(f"CANNOT RUN: {args.defaults}: {error}", file=sys.stderr)
        return 2
    if not isinstance(defaults, dict):
        print(
            f"CANNOT RUN: {args.defaults}: top level is not a JSON object",
            file=sys.stderr,
        )
        return 2

    try:
        problems = check(defaults, doc_text, args.doc.name)
    except GateError as error:
        print(f"CANNOT RUN: {args.doc}: {error}", file=sys.stderr)
        return 2

    if problems:
        for problem in problems:
            print(f"CONFIG REFERENCE DRIFT: {problem}", file=sys.stderr)
        print(
            f"{len(problems)} disagreement(s) between {args.defaults.name} and "
            f"{args.doc.name}. The defaults file is the source of truth; the reference "
            "table follows it.",
            file=sys.stderr,
        )
        return 1

    count = len(default_leaves(defaults))
    print(f"{args.doc.name} documents all {count} key(s) in {args.defaults.name}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
