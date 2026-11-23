#!/usr/bin/env python3
"""Generate the gather-block rule text in every skill that carries its markers.

    scripts/sync-gather-block.py [ROOT]           rewrite every generated block
    scripts/sync-gather-block.py --check [ROOT]   fail when any block is stale

SINGLE SOURCE OF TRUTH: `docs/conventions/gather-block/block.md`. Its text renders
into each `plugins/*/skills/*/SKILL.md` between the markers below. A skill opts in by
carrying the markers, so the markers are the consumer list and no second list is
kept. Never hand-edit a block: change block.md and re-run this script. CI runs
`--check` and rejects drift, the same contract `scripts/sync-config-cascade-semantics.py`
uses. The commands a skill gathers stay outside the markers, since they differ per skill.

Exit codes: 0 up to date or rewritten; 1 stale under `--check`, or a skill with a
`## Repository context. Gather first` heading and no markers; 2 block.md is missing or
empty, a skill's markers are malformed, no skill carries the markers, a file cannot
be read, or the arguments are wrong.
"""

from __future__ import annotations

import argparse
import difflib
import pathlib
import sys

BEGIN = "<!-- BEGIN GENERATED: gather-block. Edit docs/conventions/gather-block/block.md, then run scripts/sync-gather-block.py -->"
END = "<!-- END GENERATED: gather-block -->"
HEADING = "## Repository context. Gather first"
SOURCE = pathlib.Path("docs/conventions/gather-block/block.md")
ROOT = pathlib.Path(__file__).resolve().parent.parent


class Fail(Exception):
    def __init__(self, code: int, *lines: str):
        super().__init__("\n".join(lines))
        self.code = code


def render(text: str) -> str:
    body = text.strip()
    if not body:
        raise Fail(2, f"{SOURCE} is empty")
    return "\n".join([BEGIN, body, END])


def splice(text: str, block: str) -> str:
    start, end = text.find(BEGIN), text.find(END)
    if text.count(BEGIN) != 1 or text.count(END) != 1 or start > end:
        raise Fail(2, "expected one BEGIN and one END generated marker, BEGIN first")
    return text[:start] + block + text[end + len(END) :]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("root", nargs="?", type=pathlib.Path, default=ROOT)
    parser.add_argument(
        "--check", action="store_true", help="fail with a diff when a block is stale"
    )
    args = parser.parse_args()

    try:
        block = render((args.root / SOURCE).read_text(encoding="utf-8"))
    except OSError as exc:
        print(f"cannot read {SOURCE}: {exc}", file=sys.stderr)
        return 2
    except Fail as exc:
        print(exc, file=sys.stderr)
        return exc.code

    stale: dict[pathlib.Path, tuple[str, str]] = {}
    unmarked: list[str] = []
    consumers = 0
    for skill in sorted(args.root.glob("plugins/*/skills/*/SKILL.md")):
        rel = skill.relative_to(args.root).as_posix()
        try:
            current = skill.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"cannot read {rel}: {exc}", file=sys.stderr)
            return 2
        if BEGIN not in current and END not in current:
            if HEADING in current.splitlines():
                unmarked.append(rel)
            continue
        consumers += 1
        try:
            updated = splice(current, block)
        except Fail as exc:
            print(f"{rel}: {exc}", file=sys.stderr)
            return exc.code
        if updated != current:
            stale[skill] = (current, updated)

    if not consumers:
        print("gather-block: no skill carries the generated markers", file=sys.stderr)
        return 2
    for rel in unmarked:
        print(
            f"{rel}: '{HEADING}' has no generated gather-block markers; add them and run"
            " python3 scripts/sync-gather-block.py",
            file=sys.stderr,
        )

    if args.check and stale:
        for skill, (current, updated) in stale.items():
            rel = skill.relative_to(args.root).as_posix()
            sys.stderr.writelines(
                difflib.unified_diff(
                    current.splitlines(keepends=True),
                    updated.splitlines(keepends=True),
                    f"{rel} (committed)",
                    f"{rel} (generated)",
                )
            )
        print(
            "\ngather-block: stale. Run: python3 scripts/sync-gather-block.py",
            file=sys.stderr,
        )
        return 1
    for skill, (_, updated) in stale.items():
        skill.write_text(updated, encoding="utf-8", newline="\n")
        print(f"gather-block: rewrote {skill.relative_to(args.root).as_posix()}")
    if unmarked:
        return 1
    if not stale:
        print(f"gather-block: up to date ({consumers} skills)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
