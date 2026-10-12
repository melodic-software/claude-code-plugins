#!/usr/bin/env python3
"""Fail when the planning chain's `## Next` graph drifts from the workflow ladder.

`.claude/rules/skill-bodies-state-current-rules.md` has every skill with a
natural successor name it in a `## Next` section, and lets
`/session-flow:workflow`'s ladder win when the two disagree. Nothing checked
either half, so the graph drifted by hand: a successor that skipped a stage, a
skill nothing routed to, a target that no longer existed.

WHAT FIRES, over the chain roster in scripts/next-graph-chain.txt:

  * unresolved: a `/plugin:skill` token in any skill's `## Next` (the whole
    tree, not only the roster) names no plugins/<plugin>/skills/<skill>/SKILL.md;
  * no-next: a roster skill has no `## Next` section and the roster declares no
    `terminal:` reason for it;
  * stage-skip: a roster skill's `## Next` names a successor whose ladder stage
    lies more than one stage ahead, and a stage in between is neither
    conditional nor optional on the ladder;
  * unstaged: a roster skill's `workflow-stage` is missing or names no ladder
    stage, which would otherwise exempt its edges, and edges into it, from the
    stage-skip check;
  * orphan: no other roster skill's `## Next` names a roster skill, and the
    roster declares no `entry:` reason for it;
  * stale-roster: a roster line names a skill that does not exist.

WHERE THE LADDER COMES FROM. A skill's stage is its own `metadata:
workflow-stage:` frontmatter value. The ladder order, and which stages are
conditional or optional, are read from the numbered stage headings of
plugins/session-flow/skills/workflow/context/steps.md, which owns them; this
gate holds no second copy. A stage that is not on the ladder (`anytime`,
`operator`, `session`, `pr`) imposes no ordering, so an edge to an off-roster
skill on one never skips; a roster skill off the ladder is `unstaged`. A backward edge (a gate that fails back to an earlier stage)
never skips either.

Usage:

    scripts/check-next-graph.py [--root DIR]

Exit codes: 0 clean, 1 findings (on stderr), 2 could not run.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# The .test.sh wrapper parses this tuple to pick an interpreter.
MIN_PYTHON = (3, 7)

DEFAULT_ROOT = Path(__file__).resolve().parent.parent
ROSTER = "scripts/next-graph-chain.txt"
STEPS = "plugins/session-flow/skills/workflow/context/steps.md"

TOKEN = re.compile(r"(?<![\w/.-])/([a-z0-9][a-z0-9-]*):([a-z0-9][a-z0-9-]*)(?![\w-])")
STAGE_HEADING = re.compile(r"^## (\d+)\. (\w+)(?: \((conditional|optional)\b)?")
WORKFLOW_STAGE = re.compile(r"^\s+workflow-stage:\s*([a-z-]+)\s*$")
# A frontmatter stage matches a ladder heading word exactly; this is the one
# value whose heading word differs. A prefix match would put `pr` on `prd`.
STAGE_ALIASES = {"retro": "retrospective"}
FENCE = re.compile(r"^\s*(`{3,}|~{3,})")


class SetupError(Exception):
    """The gate could not run; exit 2."""


def skill_path(root: Path, name: str) -> Path:
    plugin, skill = name.split(":", 1)
    return root / "plugins" / plugin / "skills" / skill / "SKILL.md"


def frontmatter_stage(text: str) -> str | None:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for line in lines[1:]:
        if line.strip() == "---":
            return None
        match = WORKFLOW_STAGE.match(line)
        if match:
            return match.group(1)
    return None


def next_section(text: str) -> str | None:
    """Body of the first `## Next` section outside a fence, or None."""
    body: list[str] = []
    inside = False
    fence = None
    for line in text.splitlines():
        opener = FENCE.match(line)
        if opener:
            marker = opener.group(1)[0]
            if fence is None:
                fence = marker
            elif fence == marker:
                fence = None
            if inside:
                body.append(line)
            continue
        if fence is None and line.startswith("## "):
            if inside:
                break
            if line.rstrip() == "## Next":
                inside = True
                continue
        if inside:
            body.append(line)
    return "\n".join(body) if inside else None


def next_targets(text: str) -> list[str]:
    section = next_section(text)
    if section is None:
        return []
    return [f"{m.group(1)}:{m.group(2)}" for m in TOKEN.finditer(section)]


def read_ladder(root: Path) -> tuple[list[str], set[str]]:
    path = root / STEPS
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise SetupError(f"cannot read the workflow ladder at {STEPS}: {exc}") from exc
    order: list[tuple[int, str]] = []
    skippable: set[str] = set()
    for line in text.splitlines():
        match = STAGE_HEADING.match(line)
        if match:
            word = match.group(2).lower()
            order.append((int(match.group(1)), word))
            if match.group(3):
                skippable.add(word)
    numbers = [n for n, _ in order]
    if len(order) < 5 or numbers != list(range(1, len(order) + 1)):
        raise SetupError(
            f"{STEPS} no longer carries the numbered stage headings this gate reads "
            f"(found {numbers}); re-anchor the parser before trusting a clean run"
        )
    return [word for _, word in order], skippable


def ladder_index(stage: str | None, ladder: list[str]) -> int | None:
    """Position of a frontmatter stage on the ladder; None when it is off the ladder."""
    if not stage:
        return None
    word = STAGE_ALIASES.get(stage, stage)
    return ladder.index(word) if word in ladder else None


def read_roster(root: Path) -> dict[str, dict[str, str]]:
    path = root / ROSTER
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise SetupError(f"cannot read the chain roster at {ROSTER}: {exc}") from exc
    roster: dict[str, dict[str, str]] = {}
    for number, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        name, _, declaration = (part.strip() for part in line.partition("|"))
        if not re.fullmatch(r"[a-z0-9-]+:[a-z0-9-]+", name):
            raise SetupError(f"{ROSTER}:{number}: '{name}' is not a plugin:skill name")
        flags: dict[str, str] = {}
        if declaration:
            kind, _, reason = (part.strip() for part in declaration.partition(":"))
            if kind not in ("entry", "terminal") or not reason:
                raise SetupError(
                    f"{ROSTER}:{number}: a declaration is 'entry: <reason>' or "
                    f"'terminal: <reason>', got '{declaration}'"
                )
            flags[kind] = reason
        roster[name] = flags
    if not roster:
        raise SetupError(f"{ROSTER} names no chain skill")
    return roster


def check(root: Path) -> list[str]:
    ladder, skippable = read_ladder(root)
    roster = read_roster(root)
    findings: list[str] = []

    # Every Next target in the tree resolves.
    for skill_md in sorted((root / "plugins").glob("*/skills/*/SKILL.md")):
        text = skill_md.read_text(encoding="utf-8")
        rel = skill_md.relative_to(root).as_posix()
        for target in next_targets(text):
            if not skill_path(root, target).is_file():
                findings.append(
                    f"unresolved: {rel} '## Next' names /{target}, which no skill provides"
                )

    texts: dict[str, str] = {}
    for name in roster:
        path = skill_path(root, name)
        if not path.is_file():
            findings.append(
                f"stale-roster: {ROSTER} names {name}, which no skill provides"
            )
            continue
        texts[name] = path.read_text(encoding="utf-8")

    inbound: dict[str, set[str]] = {name: set() for name in texts}
    for name, text in texts.items():
        if next_section(text) is None and "terminal" not in roster[name]:
            findings.append(
                f"no-next: /{name} has no '## Next' section and {ROSTER} declares no terminal reason"
            )
        stage = frontmatter_stage(text)
        here = ladder_index(stage, ladder)
        if here is None:
            findings.append(
                f"unstaged: /{name} has workflow-stage '{stage or ''}', which is not a ladder "
                f"stage, so none of its edges can be checked"
            )
        for target in next_targets(text):
            if target in inbound and target != name:
                inbound[target].add(name)
            target_md = skill_path(root, target)
            if here is None or not target_md.is_file():
                continue
            there = ladder_index(
                frontmatter_stage(target_md.read_text(encoding="utf-8")), ladder
            )
            if there is None or there <= here + 1:
                continue
            skipped = [s for s in ladder[here + 1 : there] if s not in skippable]
            if skipped:
                findings.append(
                    f"stage-skip: /{name} ({ladder[here]}) routes to /{target} ({ladder[there]}), "
                    f"skipping the {', '.join(skipped)} stage the ladder never skips"
                )

    for name, sources in inbound.items():
        if not sources and "entry" not in roster[name]:
            findings.append(
                f"orphan: no chain skill's '## Next' names /{name}, and {ROSTER} declares no entry reason"
            )
    return findings


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--root", type=Path, default=DEFAULT_ROOT, help="repository root to check"
    )
    args = parser.parse_args(argv)
    try:
        findings = check(args.root.resolve())
    except SetupError as exc:
        print(f"check-next-graph: {exc}", file=sys.stderr)
        return 2
    if findings:
        for finding in findings:
            print(f"check-next-graph: {finding}", file=sys.stderr)
        print(f"check-next-graph: {len(findings)} finding(s)", file=sys.stderr)
        return 1
    print(
        "check-next-graph: the chain's Next graph resolves, follows the ladder and has no orphan"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
