#!/usr/bin/env python3
"""Pin the skill-body default sentences to config-defaults.json.

`reference/config.md` is already pinned. The README known-gaps list names the
sentences in skill bodies that still restate a default in prose. This gate
fails when those sentences disagree with the defaults file, so a default
change cannot land in one surface only.

Usage:

    scripts/check-code-metrics-skill-prose.py
    scripts/check-code-metrics-skill-prose.py --defaults FILE --root DIR

Exit codes: 0 clean, 1 a sentence disagrees, 2 the gate could not run.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

MIN_PYTHON = (3, 7)

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DEFAULTS = (
    REPO_ROOT / "plugins" / "code-metrics" / "scripts" / "config-defaults.json"
)
SKILLS = "plugins/code-metrics/skills"


def _render(value: object) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def expected_phrases(defaults: dict) -> list[tuple[str, str]]:
    """(repo-relative path, substring that must appear)."""
    duplication = defaults["duplication"]
    coverage = defaults["coverage"]
    size = defaults["size"]
    cyclomatic = defaults["complexity"]["cyclomatic"]["reference"]
    audit_duplication = f"{SKILLS}/audit-duplication/SKILL.md"
    measures = f"{SKILLS}/principles/reference/measures.md"
    audit_coverage = f"{SKILLS}/audit-coverage/SKILL.md"
    setup = f"{SKILLS}/setup/SKILL.md"
    min_tokens = f"`duplication.min_tokens` (default {_render(duplication['min_tokens'])})"
    min_lines = f"`duplication.min_lines` (default {_render(duplication['min_lines'])})"
    return [
        (audit_duplication, min_tokens),
        (audit_duplication, min_lines),
        (
            audit_duplication,
            f"`duplication.max_size` (default `{_render(duplication['max_size'])}`",
        ),
        (
            audit_duplication,
            f"`duplication.max_lines` (default `{_render(duplication['max_lines'])}`",
        ),
        (
            audit_duplication,
            f"`duplication.rollup_depth` (default {_render(duplication['rollup_depth'])}",
        ),
        (measures, min_tokens),
        (measures, min_lines),
        (
            audit_coverage,
            f"| `coverage.artifacts` | `{_render(coverage['artifacts'])}` |",
        ),
        (
            audit_coverage,
            f"| `coverage.path_prefix_strip` | `{_render(coverage['path_prefix_strip'])}` |",
        ),
        (
            audit_coverage,
            f"| `coverage.reference` | `{_render(coverage['reference'])}` |",
        ),
        (
            audit_coverage,
            f"| `coverage.crap.reference` | `{_render(coverage['crap']['reference'])}` |",
        ),
        (
            f"{SKILLS}/audit/actions/type-debt.md",
            f"`type_debt.reference`, `{_render(defaults['type_debt']['reference'])}`",
        ),
        (setup, f"the cyclomatic reference ({_render(cyclomatic)}"),
        (setup, f"the file-length reference ({_render(size['file_lines'])}"),
    ]


def _collapse(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def check(root: Path, defaults: dict) -> list[str]:
    problems: list[str] = []
    for relative, phrase in expected_phrases(defaults):
        path = root / relative
        if not path.is_file():
            problems.append(f"missing {relative}")
            continue
        # Whitespace runs collapse on both sides, so reflowing a paragraph
        # cannot fail the gate while the value is unchanged.
        text = _collapse(path.read_text(encoding="utf-8"))
        if _collapse(phrase) not in text:
            problems.append(f"{relative} does not contain {phrase!r}")
    return problems


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="check-code-metrics-skill-prose.py")
    parser.add_argument("--defaults", type=Path, default=DEFAULT_DEFAULTS)
    parser.add_argument("--root", type=Path, default=REPO_ROOT)
    args = parser.parse_args(argv)
    try:
        defaults = json.loads(args.defaults.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"check-code-metrics-skill-prose.py: {exc}", file=sys.stderr)
        return 2
    if not isinstance(defaults, dict):
        print("check-code-metrics-skill-prose.py: defaults root is not an object", file=sys.stderr)
        return 2
    problems = check(args.root, defaults)
    if problems:
        for problem in problems:
            print(f"check-code-metrics-skill-prose.py: {problem}", file=sys.stderr)
        return 1
    print(f"check-code-metrics-skill-prose.py: {len(expected_phrases(defaults))} prose defaults match")
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print(
            "check-code-metrics-skill-prose.py needs Python %d.%d or later" % MIN_PYTHON,
            file=sys.stderr,
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
