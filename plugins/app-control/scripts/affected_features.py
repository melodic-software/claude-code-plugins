#!/usr/bin/env python3
"""Map a diff to the features of an app's control skill and write affected.json.

    python3 -I affected_features.py --repo <dir> --base <ref> [--head <ref>] --out <dir> --app <app>
        [--hub <file> --control-skill <name> --source project|plugin [--skill-dir <dir>]]
        [--project-dir <dir>] [--trusted-root <dir>]

The changed files are `git diff --name-only --no-renames <base>...<head>` in <repo>, so a rename
counts its old and new path. The index is the hub's, read as reference/control-skill.md "Hub" says;
that section is the rule. --skill-dir is the control skill's base directory (default: the hub's
folder). A `sources` glob resolves against --project-dir (default: the top of <repo>): `**` matches
across `/`, `*` and `?` match within one path segment, and every other character matches itself.
Without --hub, features is empty and the note says so. --trusted-root refuses a hub or base
directory outside it. Exit 0: <out>/affected.json written. Exit 1: refused, reason on stderr.
Exit 2: usage.
"""

import argparse
import json
import os
import re
import subprocess
import sys

ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
INDEX = re.compile(r"^- .*\|\s*(features/|entry points:)")
FENCE = re.compile(r"\s*(```|~~~)")


class Refused(Exception):
    pass


def git(top, *args):
    res = subprocess.run(
        ["git", "--no-replace-objects", "-C", top, "-c", "core.fsmonitor=false", *args],
        capture_output=True,
        env=ENV,
        check=False,
    )
    if res.returncode != 0:
        raise Refused(f"git {args[0]} failed: {res.stderr.decode(errors='replace').strip()}")
    return res.stdout


def glob_re(glob):
    out, i = [], 0
    while i < len(glob):
        if glob.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif glob.startswith("**", i):
            out.append(".*")
            i += 2
        elif glob[i] == "*":
            out.append("[^/]*")
            i += 1
        elif glob[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(glob[i]))
            i += 1
    return re.compile("".join(out))


def unfenced(text):
    fence = False
    for line in text.splitlines():
        if FENCE.match(line):
            fence = not fence
        elif not fence:
            yield line


def section(lines, name):
    inside = False
    for line in lines:
        if line.startswith("## "):
            inside = line[3:].strip() == name
        elif inside and line.strip():
            yield line.strip()


def index_lines(lines):
    """Yield (title, path, globs) for each index line."""
    for line in lines:
        if not INDEX.match(line):
            continue
        fields = [f.strip() for f in line[2:].split("|")]
        if len(fields) < 4 or not fields[3].startswith("sources:"):
            continue
        globs = [g.strip() for g in fields[3][len("sources:") :].split(",") if g.strip()]
        yield fields[0], fields[1], [glob_re(g) for g in globs]


def entry_point(line):
    s = re.sub(r"^[-*]\s+", "", line)
    m = re.fullmatch(r"(.*?)(?::\s*|\s+)not driven:\s*(.*)", s)
    if m:
        return {"text": m[1], "driven": False, "reason": m[2] or None}
    m = re.fullmatch(r"(.*?)(?::\s*|\s+)not driven", s)
    if m:
        return {"text": m[1], "driven": False, "reason": None}
    m = re.fullmatch(r"(.*?)(?::\s*|\s+)driven", s)
    if m:
        return {"text": m[1], "driven": True, "reason": None}
    return {"text": s, "driven": False, "reason": None}


def feature_id(path):
    fid = path[len("features/") :]
    return fid[: -len("/README.md")] if fid.endswith("/README.md") else fid[: -len(".md")]


def inside(path, root):
    return os.path.commonpath([path, root]) == root


class Mapper:
    def __init__(self, skill_dir, rel):
        self.skill_dir = skill_dir
        self.rel = rel
        self.features = {}
        self.matched = set()
        self.notes = []

    def read(self, path):
        full = os.path.realpath(os.path.join(self.skill_dir, path))
        if not re.fullmatch(r"features/.+\.md", path) or not inside(full, self.skill_dir):
            self.notes.append(f"{path} is not a feature file inside the control skill")
            return None
        try:
            with open(full, encoding="utf-8") as f:
                return list(unfenced(f.read()))
        except OSError:
            self.notes.append(f"{path} could not be read")
            return None

    def visit(self, lines, files, seen):
        for title, path, globs in index_lines(lines):
            hits = [
                f
                for f in files
                if self.rel[f] is not None and any(g.fullmatch(self.rel[f]) for g in globs)
            ]
            if not hits:
                continue
            text = self.read(path)
            subs = list(section(text, "Sub-features")) if text else []
            if path not in seen and any(INDEX.match(s) for s in subs):
                self.visit(subs, hits, seen | {path})
                continue
            fid = feature_id(path) if path.startswith("features/") else path
            feature = self.features.setdefault(
                fid,
                {
                    "id": fid,
                    "title": title,
                    "entry_points": [entry_point(e) for e in section(text or [], "Entry points")],
                    "matched_files": [],
                },
            )
            feature["matched_files"] = sorted(set(feature["matched_files"]) | set(hits))
            self.matched.update(hits)


def run(a):
    if not os.path.isdir(a.repo):
        raise Refused(f"{a.repo} is not a directory")
    top = os.path.realpath(os.fsdecode(git(a.repo, "rev-parse", "--show-toplevel").rstrip(b"\n")))
    out = git(
        top,
        "diff",
        "--name-only",
        "--no-renames",
        "-z",
        "--no-ext-diff",
        "--no-textconv",
        "--end-of-options",
        f"{a.base}...{a.head}",
        "--",
    )
    files = sorted({os.fsdecode(p) for p in out.split(b"\0") if p})

    project = os.path.realpath(a.project_dir or top)
    if not inside(project, top):
        raise Refused(f"--project-dir {a.project_dir} is outside the repository")
    prefix = os.path.relpath(project, top).replace(os.sep, "/")
    rel = {}
    for f in files:
        if prefix == ".":
            rel[f] = f
        else:
            rel[f] = f[len(prefix) + 1 :] if f.startswith(prefix + "/") else None

    trusted = os.path.realpath(a.trusted_root) if a.trusted_root else None
    result = {
        "app": a.app,
        "control_skill": a.control_skill,
        "source": a.source if a.hub else "none",
        "trusted_root": trusted,
        "base": a.base,
        "head": a.head,
        "features": [],
        "unmatched_files": files,
        "note": "No control skill: nothing matched",
    }
    if a.hub:
        hub = os.path.realpath(a.hub)
        skill_dir = os.path.realpath(a.skill_dir or os.path.dirname(hub))
        if trusted and not (inside(hub, trusted) and inside(skill_dir, trusted)):
            raise Refused(f"control skill {a.hub} is outside --trusted-root {a.trusted_root}")
        try:
            with open(hub, encoding="utf-8") as f:
                hub_lines = list(unfenced(f.read()))
        except OSError:
            raise Refused(f"control skill {a.hub} could not be read") from None
        m = Mapper(skill_dir, rel)
        m.visit(hub_lines, files, frozenset())
        result["features"] = list(m.features.values())
        result["unmatched_files"] = [f for f in files if f not in m.matched]
        notes = m.notes
        if not m.features:
            notes = [f"control skill present, {len(files)} files unmatched", *notes]
        result["note"] = "; ".join(notes) or None

    os.makedirs(a.out, exist_ok=True)
    path = os.path.join(a.out, "affected.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
        f.write("\n")
    print(path)


def main(argv):
    p = argparse.ArgumentParser(prog="affected_features.py")
    p.add_argument("--repo", required=True)
    p.add_argument("--base", required=True)
    p.add_argument("--head", default="HEAD")
    p.add_argument("--out", required=True)
    p.add_argument("--app", required=True)
    p.add_argument("--hub")
    p.add_argument("--skill-dir")
    p.add_argument("--control-skill")
    p.add_argument("--source", choices=["project", "plugin"])
    p.add_argument("--project-dir")
    p.add_argument("--trusted-root")
    a = p.parse_args(argv[1:])
    if a.hub and not (a.control_skill and a.source):
        p.error("--hub needs --control-skill and --source")
    if not a.hub and (a.control_skill or a.source or a.skill_dir):
        p.error("--control-skill, --source and --skill-dir need --hub")
    if a.base.startswith("-") or a.head.startswith("-"):
        p.error("--base and --head take a ref")
    try:
        run(a)
    except Refused as why:
        print(f"affected_features.py: {why}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
