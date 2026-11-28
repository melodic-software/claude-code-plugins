"""Report skills whose ## Next and ## Related differ from scripts/skill-links.json.

Usage: python3 -I scripts/check-skill-links.py <repository root>

Run through scripts/check-skill-links.sh. The rules are
.claude/rules/skill-bodies-state-current-rules.md. Report-only: exit 0 whenever it ran.
"""

import json
import re
import sys
from pathlib import Path

TARGET = re.compile(r"(?<![\w/.-])/([a-z0-9-]+):([a-z0-9-]+)")
SECTION = re.compile(r"^## (.+?)[ \t]*$")
FENCE = re.compile(r"^\s*(```|~~~)")
IF_ENABLED = re.compile(r"\s*\(if enabled\)")


def die(message):
    print(f"check-skill-links: {message}", file=sys.stderr)
    sys.exit(2)


def body_lines(text):
    lines = text.splitlines()
    start = 0
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                start = i + 1
                break
    return [(n + 1, lines[n]) for n in range(start, len(lines))]


def targets(text):
    return {f"/{p}:{s}" for p, s in TARGET.findall(text)}


def sections(lines):
    found = {"Next": set(), "Related": set()}
    outside = []
    current = None
    fenced = False
    for number, line in lines:
        if FENCE.match(line):
            fenced = not fenced
        heading = None if fenced else SECTION.match(line)
        if heading:
            current = heading.group(1) if heading.group(1) in found else None
            continue
        if current:
            found[current] |= targets(line)
        elif not fenced:
            outside.append((number, line))
    return found, outside


def dependencies(manifest):
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return set()
    except (OSError, ValueError) as err:
        die(f"cannot read {manifest}: {type(err).__name__}: {err}")
    if not isinstance(data, dict):
        die(f"{manifest}: not a JSON object")
    names = set()
    for dep in data.get("dependencies") or []:
        name = dep.get("name") if isinstance(dep, dict) else dep
        if isinstance(name, str):
            names.add(name.split("@", 1)[0])
    return names


def unguarded(line, own, plugins, declared):
    for match in TARGET.finditer(line):
        plugin = match.group(1)
        if plugin == own or plugin in declared or plugin not in plugins:
            continue
        end = match.end()
        if match.start() > 0 and line[match.start() - 1] == "`":
            close = line.find("`", end)
            end = close + 1 if close != -1 else end
        if not IF_ENABLED.match(line, end):
            yield match.group(0)


def describe(name, want, have):
    parts = []
    if want - have:
        parts.append(f"{name} missing {' '.join(sorted(want - have))}")
    if have - want:
        parts.append(f"{name} extra {' '.join(sorted(have - want))}")
    return parts


def main():
    if len(sys.argv) != 2:
        die("usage: check-skill-links.py <repository root>")
    root = Path(sys.argv[1])
    data_file = root / "scripts" / "skill-links.json"
    try:
        rows = json.loads(data_file.read_text(encoding="utf-8"))["skills"]
    except (OSError, ValueError, KeyError, TypeError) as err:
        die(f"cannot read {data_file}: {type(err).__name__}: {err}")
    if not isinstance(rows, dict):
        die(f"{data_file}: 'skills' is not an object")
    for key, row in rows.items():
        if not isinstance(row, dict) or not all(
            isinstance(row.get(k), list) and all(isinstance(v, str) for v in row[k])
            for k in ("next", "related")
        ):
            die(f"{data_file}: row {key!r} needs string lists 'next' and 'related'")
    plugins_dir = root / "plugins"
    if not plugins_dir.is_dir():
        die(f"no plugins directory under {root}")
    plugins = {p.name for p in plugins_dir.iterdir() if p.is_dir()}

    differing, no_row, wording = [], [], []
    seen = set()
    for skill_md in sorted(plugins_dir.glob("*/skills/*/SKILL.md")):
        plugin, skill = skill_md.parts[-4], skill_md.parts[-2]
        key = f"{plugin}:{skill}"
        seen.add(key)
        rel = skill_md.relative_to(root).as_posix()
        try:
            text = skill_md.read_text(encoding="utf-8")
        except (OSError, ValueError) as err:
            die(f"cannot read {rel}: {type(err).__name__}: {err}")
        found, outside = sections(body_lines(text))
        row = rows.get(key)
        if row is None:
            no_row.append(key)
        else:
            parts = describe("next", targets(" ".join(row["next"])), found["Next"])
            parts += describe(
                "related", targets(" ".join(row["related"])), found["Related"]
            )
            if parts:
                differing.append(f"{key}: {'; '.join(parts)}")
        declared = dependencies(plugins_dir / plugin / ".claude-plugin" / "plugin.json")
        for number, line in outside:
            for target in unguarded(line, plugin, plugins, declared):
                wording.append(f'{rel}:{number}: {target} lacks "(if enabled)"')
    stale = sorted(set(rows) - seen)

    for line in differing:
        print(f"DIFFERS: {line}", file=sys.stderr)
    for key in no_row:
        print(f"NO ROW: {key}", file=sys.stderr)
    for key in stale:
        print(f"ROW WITHOUT SKILL: {key}", file=sys.stderr)
    for line in wording:
        print(f"WORDING: {line}", file=sys.stderr)
    print(
        f"check-skill-links: {len(seen)} skills; {len(differing)} differ from the table, "
        f"{len(no_row)} have no row, {len(stale)} rows name no skill, "
        f"{len(wording)} optional-plugin mentions lack (if enabled). Report only."
    )


if __name__ == "__main__":
    main()
