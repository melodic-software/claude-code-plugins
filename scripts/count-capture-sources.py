#!/usr/bin/env python3
"""Count the pull requests the per-pull-request capture would drive, under the control skill's
`sources:` globs as written and as widened, before any widening is applied.

    python3 -I scripts/count-capture-sources.py [--days 14] [--ref origin/main] [--hub <file>]
        [--repo <dir>] [--json]

A merged pull request is a first-parent commit on --ref, committed in the last --days days, whose
subject ends in `(#<n>)` (a squash merge) or starts `Merge pull request #<n> `. Its files are that
commit's `git diff --name-only --no-renames` against its first parent. Each file list goes through
the capture's own matcher, plugins/app-control/scripts/affected_features.py, twice: against the
hub's feature lines as written, and with each `plugins/<plugin>/skills/*/SKILL.md` glob replaced by
`plugins/<plugin>/skills/**`, `plugins/<plugin>/scripts/**` and `plugins/<plugin>/agents/**`. The
hub and its feature files are read from the working tree, the history from --ref. It reads git
history and the control skill only, and starts no capture. Exit 0: report printed. Exit 1: git or
the hub could not be read, reason on stderr. Exit 2: usage.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "plugins/app-control/scripts"))

import affected_features as af  # noqa: E402

HUB = ".claude/skills/control-claude-code-plugins/SKILL.md"
SKILL_GLOB = re.compile(r"plugins/([^/*?]+)/skills/\*/SKILL\.md")
WIDE_DIRS = ("skills", "scripts", "agents")
MERGED = re.compile(r"\(#(\d+)\)$|^Merge pull request #(\d+) ")


def widen(line: str) -> str:
    """The index line with each plugin's SKILL.md glob replaced by the wider globs."""
    if not af.INDEX.match(line):
        return line
    fields = line[2:].split("|")
    if len(fields) < 4 or not fields[3].strip().startswith("sources:"):
        return line
    globs = [g.strip() for g in fields[3].strip()[len("sources:") :].split(",") if g.strip()]
    wide: list[str] = []
    for glob in globs:
        m = SKILL_GLOB.fullmatch(glob)
        for new in [f"plugins/{m[1]}/{d}/**" for d in WIDE_DIRS] if m else [glob]:
            if new not in wide:
                wide.append(new)
    fields[3] = " sources: " + ", ".join(wide) + (" " if len(fields) > 4 else "")
    return "- " + "|".join(fields)


def merged_prs(top: str, ref: str, days: int) -> list[tuple[int, str]]:
    """(pull request number, commit) for each merge on ref's first-parent line in the window."""
    out = af.git(
        top, "log", "--first-parent", f"--since={days} days ago", "--format=%H %s",
        "--end-of-options", ref, "--",
    )
    prs = []
    for line in out.decode(errors="replace").splitlines():
        sha, _, subject = line.partition(" ")
        m = MERGED.search(subject)
        if m:
            prs.append((int(m[1] or m[2]), sha))
    return prs


def changed_files(top: str, sha: str) -> list[str]:
    out = af.git(
        top, "diff", "--name-only", "--no-renames", "-z", "--no-ext-diff", "--no-textconv",
        "--end-of-options", f"{sha}^", sha, "--",
    )
    return sorted({os.fsdecode(p) for p in out.split(b"\0") if p})


def features(skill_dir: str, lines: list[str], files: list[str]) -> list[str]:
    mapper = af.Mapper(skill_dir, {f: f for f in files})
    mapper.visit(lines, files, frozenset())
    return sorted(mapper.features)


def count(repo: str, ref: str, days: int, hub: str) -> dict:
    top = os.path.realpath(os.fsdecode(af.git(repo, "rev-parse", "--show-toplevel").rstrip(b"\n")))
    hub_path = os.path.realpath(os.path.join(top, hub))
    try:
        with open(hub_path, encoding="utf-8") as f:
            current = list(af.unfenced(f.read()))
    except OSError:
        raise af.Refused(f"control skill {hub} could not be read") from None
    wider = [widen(line) for line in current]
    skill_dir = os.path.dirname(hub_path)
    rows = []
    for number, sha in merged_prs(top, ref, days):
        files = changed_files(top, sha)
        rows.append({
            "pr": number,
            "commit": sha,
            "current": features(skill_dir, current, files),
            "wider": features(skill_dir, wider, files),
        })
    totals = {
        name: {
            "prs_driven": sum(1 for r in rows if r[name]),
            "features_driven": sum(len(r[name]) for r in rows),
        }
        for name in ("current", "wider")
    }
    return {"ref": ref, "days": days, "hub": hub, "prs": len(rows), "totals": totals, "rows": rows}


def report(result: dict) -> str:
    t, n = result["totals"], result["prs"]
    lines = [
        f"Pull requests merged on {result['ref']} in the last {result['days']} days: {n}",
        f"Control skill: {result['hub']}",
        "A driven pull request matches at least one feature; each one is one capture.",
        "",
    ]
    for name in ("current", "wider"):
        lines.append(
            f"{name}: {t[name]['prs_driven']} of {n} pull requests driven, "
            f"{t[name]['features_driven']} feature drives"
        )
    lines += [
        "",
        "Extra captures under the wider pattern: "
        f"{t['wider']['prs_driven'] - t['current']['prs_driven']} pull requests, "
        f"{t['wider']['features_driven'] - t['current']['features_driven']} feature drives",
    ]
    changed = [r for r in result["rows"] if r["current"] != r["wider"]]
    if changed:
        lines += ["", "Pull requests whose features change (current -> wider):"]
        for r in changed:
            lines.append(
                f"#{r['pr']}: {len(r['current'])} -> {len(r['wider'])} ({', '.join(r['wider'])})"
            )
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(prog="count-capture-sources.py")
    p.add_argument("--repo", default=".")
    p.add_argument("--ref", default="origin/main")
    p.add_argument("--days", type=int, default=14)
    p.add_argument("--hub", default=HUB)
    p.add_argument("--json", action="store_true")
    a = p.parse_args(argv[1:])
    if a.days < 1:
        p.error("--days takes a positive number")
    if a.ref.startswith("-"):
        p.error("--ref takes a ref")
    try:
        result = count(a.repo, a.ref, a.days, a.hub)
    except af.Refused as why:
        print(f"count-capture-sources.py: {why}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2) if a.json else report(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
