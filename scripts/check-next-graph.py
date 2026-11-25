#!/usr/bin/env python3
"""Fail when a skill's `## Next` drifts from the workflow stage map.

The stage map, plugins/session-flow/skills/workflow/reference/stages.yaml, holds
the ladder as data: stage order, optional and conditional flags, the entry skill
per stage, and the declared loop-backs and skips. This gate holds every skill
with a `metadata: workflow-stage:` to it.

WHAT FIRES:

  * unresolved: a `/plugin:skill` token in any skill's `## Next` names no
    plugins/<plugin>/skills/<skill>/SKILL.md;
  * stage-entry: a `## Next` bullet written `the <stage> stage (/plugin:skill)`
    names a skill other than the map's entry skill for that stage, or a stage
    the map does not hold or gives no entry skill;
  * unstaged: a skill's workflow-stage is neither a ladder stage, an alias, nor
    an off-ladder value;
  * loop-back: a `## Next` successor sits on an earlier ladder stage and no
    `loop-backs` declaration covers the edge;
  * stage-skip: a successor sits more than one stage ahead, a stage in between
    carries no flag, and no `skips` declaration covers the edge;
  * entry skills: the map names a skill that does not exist (stale-entry),
    whose workflow-stage is another stage (entry-stage), that has no `## Next`
    and no `terminal:` reason (no-next), or that no skill's `## Next` names and
    has no `inbound:` reason (orphan);
  * stale-declaration: a loop-back or skip names a stage or skill that does not
    exist;
  * map-drift: the map's stage names differ from the numbered stage headings of
    plugins/session-flow/skills/workflow/context/steps.md.

A declaration's `from` and `to` each match a stage id or a plugin:skill, and
`from: any` matches every source. An off-ladder stage (`anytime`, `operator`, `session`, `pr`) imposes no order.

--fix rewrites, in place, each stage bullet's token to the map's entry skill,
and, with --renames FILE (lines of `plugin:old plugin:new`), each renamed token
in `## Next` and `## Related`; then it checks.

Usage:

    scripts/check-next-graph.py [--root DIR] [--fix] [--renames FILE]

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
STAGE_MAP = "plugins/session-flow/skills/workflow/reference/stages.yaml"
STEPS = "plugins/session-flow/skills/workflow/context/steps.md"

TOKEN = re.compile(r"(?<![\w/.-])/([a-z0-9][a-z0-9-]*):([a-z0-9][a-z0-9-]*)(?![\w-])")
STAGE_TARGET = re.compile(
    r"\bthe ([A-Za-z][A-Za-z -]*?) stage \(`?/([a-z0-9][a-z0-9-]*:[a-z0-9][a-z0-9-]*)"
)
SKILL_NAME = re.compile(r"[a-z0-9-]+:[a-z0-9-]+")
STEPS_HEADING = re.compile(r"^## (\d+)\. ([^(:]+?)\s*(?:\(|:|$)")
WORKFLOW_STAGE = re.compile(r"^\s+workflow-stage:\s*[\"']?([a-z-]+)[\"']?\s*$")
FENCE = re.compile(r"^\s*(`{3,}|~{3,})")
FLAGS = ("optional", "conditional")
ANY = "any"


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


def section_span(lines: list[str], heading: str) -> tuple[int, int] | None:
    """Line range of the body under `## <heading>`, skipping fenced blocks."""
    start = None
    fence = None
    for number, line in enumerate(lines):
        opener = FENCE.match(line)
        if opener:
            marker = opener.group(1)[0]
            if fence is None:
                fence = marker
            elif fence == marker:
                fence = None
            continue
        if fence is None and line.startswith("## "):
            if start is not None:
                return start, number
            if line.rstrip() == f"## {heading}":
                start = number + 1
    return (start, len(lines)) if start is not None else None


def next_section(text: str) -> str | None:
    lines = text.splitlines()
    span = section_span(lines, "Next")
    return None if span is None else "\n".join(lines[span[0] : span[1]])


def next_targets(text: str) -> list[str]:
    section = next_section(text)
    if section is None:
        return []
    return [f"{m.group(1)}:{m.group(2)}" for m in TOKEN.finditer(section)]


class StageMap:
    def __init__(self, data: object) -> None:
        if not isinstance(data, dict) or not isinstance(data.get("stages"), list):
            raise SetupError(f"{STAGE_MAP} has no 'stages' list")
        self.ladder: list[str] = []
        self.titles: list[str] = []
        self.names: dict[str, str] = {}
        self.flagged: set[str] = set()
        self.entries: dict[str, str] = {}
        self.terminal: set[str] = set()
        self.inbound: set[str] = set()
        for number, stage in enumerate(data["stages"], 1):
            if (
                not isinstance(stage, dict)
                or not stage.get("id")
                or not stage.get("name")
            ):
                raise SetupError(
                    f"{STAGE_MAP}: stage {number} needs an 'id' and a 'name'"
                )
            sid = str(stage["id"])
            self.ladder.append(sid)
            self.titles.append(str(stage["name"]).lower())
            self.names[self.titles[-1]] = sid
            self.names[sid] = sid
            flag = stage.get("flag")
            if flag is not None and flag not in FLAGS:
                raise SetupError(
                    f"{STAGE_MAP}: stage {sid} flag '{flag}' is not one of {FLAGS}"
                )
            if flag:
                self.flagged.add(sid)
            entry = stage.get("entry")
            if entry is not None:
                if not SKILL_NAME.fullmatch(str(entry)):
                    raise SetupError(
                        f"{STAGE_MAP}: stage {sid} entry '{entry}' is not plugin:skill"
                    )
                self.entries[sid] = str(entry)
                if stage.get("terminal"):
                    self.terminal.add(sid)
                if stage.get("inbound"):
                    self.inbound.add(sid)
        if len(self.ladder) < 5 or len(set(self.ladder)) != len(self.ladder):
            raise SetupError(f"{STAGE_MAP} needs at least five distinct stages")
        self.off_ladder = {str(s) for s in data.get("off-ladder") or []}
        self.aliases = {str(k): str(v) for k, v in (data.get("aliases") or {}).items()}
        self.loop_backs = self._edges(data, "loop-backs")
        self.skips = self._edges(data, "skips")

    @staticmethod
    def _edges(data: dict, key: str) -> list[tuple[str, str]]:
        edges = []
        for number, edge in enumerate(data.get(key) or [], 1):
            if not isinstance(edge, dict) or not all(
                str(edge.get(field) or "").strip() for field in ("from", "to", "reason")
            ):
                raise SetupError(
                    f"{STAGE_MAP}: {key} entry {number} needs 'from', 'to' and 'reason'"
                )
            edges.append((str(edge["from"]), str(edge["to"])))
        return edges

    def index(self, stage: str | None) -> int | None:
        if not stage:
            return None
        word = self.aliases.get(stage, stage)
        return self.ladder.index(word) if word in self.ladder else None

    def known(self, stage: str) -> bool:
        return self.index(stage) is not None or stage in self.off_ladder


def read_map(root: Path) -> StageMap:
    try:
        import yaml
    except ModuleNotFoundError as exc:
        raise SetupError(
            "PyYAML is required to read the stage map (pip install pyyaml; CI pins it in "
            ".github/requirements-ci.txt)"
        ) from exc
    try:
        text = (root / STAGE_MAP).read_text(encoding="utf-8")
    except OSError as exc:
        raise SetupError(f"cannot read the stage map at {STAGE_MAP}: {exc}") from exc
    try:
        return StageMap(yaml.safe_load(text))
    except yaml.YAMLError as exc:
        raise SetupError(f"{STAGE_MAP} is not valid YAML: {exc}") from exc


def steps_names(root: Path) -> list[str] | None:
    try:
        text = (root / STEPS).read_text(encoding="utf-8")
    except OSError:
        return None
    return [
        m.group(2).strip().lower()
        for m in map(STEPS_HEADING.match, text.splitlines())
        if m
    ]


def declared(
    edges: list[tuple[str, str]], source: tuple[str, str], target: tuple[str, str]
) -> bool:
    return any((a == ANY or a in source) and b in target for a, b in edges)


def check(root: Path) -> list[str]:
    stage_map = read_map(root)
    findings: list[str] = []

    names = steps_names(root)
    if names is not None and names != stage_map.titles:
        findings.append(
            f"map-drift: {STAGE_MAP} names the stages {stage_map.titles}, but {STEPS} numbers {names}"
        )

    stages: dict[str, str | None] = {}
    inbound: dict[str, int] = {}
    for skill_md in sorted((root / "plugins").glob("*/skills/*/SKILL.md")):
        name = f"{skill_md.parts[-4]}:{skill_md.parts[-2]}"
        stages[name] = frontmatter_stage(skill_md.read_text(encoding="utf-8"))

    for skill_md in sorted((root / "plugins").glob("*/skills/*/SKILL.md")):
        text = skill_md.read_text(encoding="utf-8")
        rel = skill_md.relative_to(root).as_posix()
        name = f"{skill_md.parts[-4]}:{skill_md.parts[-2]}"
        stage = stages[name]
        section = next_section(text) or ""
        targets = [f"{m.group(1)}:{m.group(2)}" for m in TOKEN.finditer(section)]

        for target in dict.fromkeys(targets):
            if target not in stages:
                findings.append(
                    f"unresolved: {rel} '## Next' names /{target}, which no skill provides"
                )
            elif target != name:
                inbound[target] = inbound.get(target, 0) + 1

        for match in STAGE_TARGET.finditer(section):
            word, target = match.group(1).lower(), match.group(2)
            sid = stage_map.names.get(word) or stage_map.names.get(
                stage_map.aliases.get(word, "")
            )
            entry = stage_map.entries.get(sid or "")
            if entry is None:
                findings.append(
                    f"stage-entry: {rel} '## Next' routes to 'the {match.group(1)} stage', "
                    f"which {STAGE_MAP} gives no entry skill"
                )
            elif target != entry:
                findings.append(
                    f"stage-entry: {rel} '## Next' names /{target} for the {sid} stage, "
                    f"whose entry skill is /{entry} (run --fix)"
                )

        if stage is None:
            continue
        if not stage_map.known(stage):
            findings.append(
                f"unstaged: /{name} has workflow-stage '{stage}', which {STAGE_MAP} holds as "
                f"neither a stage, an alias nor an off-ladder value"
            )
            continue
        here = stage_map.index(stage)
        if here is None:
            continue
        for target in dict.fromkeys(targets):
            there = stage_map.index(stages.get(target))
            if there is None or target == name:
                continue
            source = (name, stage_map.ladder[here])
            sink = (target, stage_map.ladder[there])
            if there < here:
                if not declared(stage_map.loop_backs, source, sink):
                    findings.append(
                        f"loop-back: /{name} ({source[1]}) routes back to /{target} ({sink[1]}), "
                        f"and {STAGE_MAP} declares no loop-back for it"
                    )
                continue
            skipped = [
                s
                for s in stage_map.ladder[here + 1 : there]
                if s not in stage_map.flagged
            ]
            if skipped and not declared(stage_map.skips, source, sink):
                findings.append(
                    f"stage-skip: /{name} ({source[1]}) routes to /{target} ({sink[1]}), "
                    f"skipping the {', '.join(skipped)} stage the ladder never skips"
                )

    for sid, entry in stage_map.entries.items():
        if entry not in stages:
            findings.append(
                f"stale-entry: {STAGE_MAP} names /{entry} for {sid}, which no skill provides"
            )
            continue
        if stage_map.index(stages[entry]) != stage_map.ladder.index(sid):
            findings.append(
                f"entry-stage: /{entry} enters the {sid} stage, but its workflow-stage is "
                f"'{stages[entry] or ''}'"
            )
        if next_section(
            skill_path(root, entry).read_text(encoding="utf-8")
        ) is None and (sid not in stage_map.terminal):
            findings.append(
                f"no-next: /{entry} has no '## Next' section and {STAGE_MAP} gives the {sid} "
                f"stage no terminal reason"
            )
        if not inbound.get(entry) and sid not in stage_map.inbound:
            findings.append(
                f"orphan: no skill's '## Next' names /{entry}, and {STAGE_MAP} gives the {sid} "
                f"stage no inbound reason"
            )

    for key, edges in (
        ("loop-backs", stage_map.loop_backs),
        ("skips", stage_map.skips),
    ):
        for edge in edges:
            for end in edge:
                if end not in stages and end not in stage_map.ladder and end != ANY:
                    findings.append(
                        f"stale-declaration: {STAGE_MAP} {key} names '{end}', which is neither a "
                        f"stage nor a skill"
                    )
    return findings


def read_renames(path: Path) -> dict[str, str]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise SetupError(f"cannot read the rename list at {path}: {exc}") from exc
    renames: dict[str, str] = {}
    for number, raw in enumerate(lines, 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 2 or not all(SKILL_NAME.fullmatch(p) for p in parts):
            raise SetupError(
                f"{path}:{number}: a rename line is 'plugin:old plugin:new', got '{raw}'"
            )
        renames[parts[0]] = parts[1]
    return renames


def fix(root: Path, renames: dict[str, str]) -> list[str]:
    stage_map = read_map(root)

    def stage_token(match: re.Match) -> str:
        word = match.group(1).lower()
        entry = stage_map.entries.get(stage_map.names.get(word, ""))
        if entry is None:
            return match.group(0)
        return match.group(0)[: match.start(2) - match.start(0)] + entry

    def renamed(match: re.Match) -> str:
        name = f"{match.group(1)}:{match.group(2)}"
        return f"/{renames.get(name, name)}"

    changed: list[str] = []
    for skill_md in sorted((root / "plugins").glob("*/skills/*/SKILL.md")):
        text = skill_md.read_text(encoding="utf-8")
        lines = text.split("\n")
        for heading in ("Next", "Related"):
            span = section_span(lines, heading)
            if span is None:
                continue
            for number in range(*span):
                line = lines[number]
                if heading == "Next":
                    line = STAGE_TARGET.sub(stage_token, line)
                if renames:
                    line = TOKEN.sub(renamed, line)
                lines[number] = line
        updated = "\n".join(lines)
        if updated != text:
            skill_md.write_text(updated, encoding="utf-8")
            changed.append(skill_md.relative_to(root).as_posix())
    return changed


def main(argv: list[str]) -> int:
    summary = (__doc__ or "check-next-graph").splitlines()[0]
    parser = argparse.ArgumentParser(description=summary)
    parser.add_argument(
        "--root", type=Path, default=DEFAULT_ROOT, help="repository root to check"
    )
    parser.add_argument(
        "--fix",
        action="store_true",
        help="rewrite stage-bullet and renamed tokens, then check",
    )
    parser.add_argument(
        "--renames", type=Path, help="with --fix: file of 'plugin:old plugin:new' lines"
    )
    args = parser.parse_args(argv)
    if args.renames and not args.fix:
        parser.error("--renames needs --fix")
    root = args.root.resolve()
    try:
        if args.fix:
            renames = read_renames(args.renames) if args.renames else {}
            for rel in fix(root, renames):
                print(f"check-next-graph: fixed {rel}")
        findings = check(root)
    except SetupError as exc:
        print(f"check-next-graph: {exc}", file=sys.stderr)
        return 2
    if findings:
        for finding in findings:
            print(f"check-next-graph: {finding}", file=sys.stderr)
        print(f"check-next-graph: {len(findings)} finding(s)", file=sys.stderr)
        return 1
    print("check-next-graph: every '## Next' resolves and follows the stage map")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
