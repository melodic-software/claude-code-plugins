#!/usr/bin/env python3
"""Report each use of a retired vocabulary sense in the files given.

The senses, their rules and their allowlists live in vocabulary-senses.json
beside this script. A rule is a `match` regex, plus an optional `near` regex
that must also match on the same line, so a word is reported only in the
context of its retired sense. An allowlist entry is a `path` glob or a
`phrase` regex on the same line, each with the reason the sense stays. All
regexes are case-insensitive.

Always excluded, even when named: docs/adr/, docs/upstream/, docs/standards/,
any CHANGELOG file, and this checker's own files, which quote the senses.

Usage:

    scripts/check-vocabulary.py [--sense <id>]... [<path>...]

With no --sense, every sense is checked; with no path, every tracked file in
the repository. A directory path checks the tracked files under it.

Output: `<path>:<line>: <sense>: <text>`, one row per matching line and sense.
Exit codes: 0 no match, 1 at least one match, 2 could not run.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

# `from __future__ import annotations` needs 3.7; the .test.sh wrapper parses
# this tuple to pick an interpreter.
MIN_PYTHON = (3, 7)

SCRIPT = Path(__file__).resolve()
REPO_ROOT = SCRIPT.parent.parent
DATA = SCRIPT.parent / "vocabulary-senses.json"

EXCLUDED_PREFIXES = ("docs/adr/", "docs/upstream/", "docs/standards/")
SELF_FILES = frozenset(
    f"scripts/{name}"
    for name in (
        SCRIPT.name,
        DATA.name,
        "check-vocabulary.test.sh",
        "test_check_vocabulary.py",
    )
)
TEXT_LIMIT = 200


class Unusable(Exception):
    pass


def glob_regex(glob: str):
    out = []
    i = 0
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
    return re.compile("".join(out) + r"\Z")


def compile_regex(pattern, where: str):
    if not isinstance(pattern, str) or not pattern:
        raise Unusable(f"{where}: expected a non-empty regex string")
    try:
        return re.compile(pattern, re.IGNORECASE)
    except re.error as exc:
        raise Unusable(f"{where}: bad regex {pattern!r}: {exc}") from exc


def objects(parent: dict, key: str, where: str) -> list:
    items = parent.get(key) or []
    if not isinstance(items, list) or not all(isinstance(i, dict) for i in items):
        raise Unusable(f"{where}: {key} must be a list of objects")
    return items


def load_senses(path: Path) -> list:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise Unusable(f"cannot read {path.name}: {exc}") from exc
    if not isinstance(data, dict):
        raise Unusable(f"{path.name}: expected a JSON object")
    senses = []
    seen = set()
    for n, raw in enumerate(objects(data, "senses", path.name)):
        sid = raw.get("id")
        if not isinstance(sid, str) or not sid or sid in seen:
            raise Unusable(f"sense {n}: missing or duplicate id")
        seen.add(sid)
        rules = []
        for k, rule in enumerate(objects(raw, "rules", sid)):
            where = f"{sid} rule {k}"
            near = rule.get("near")
            rules.append(
                (
                    compile_regex(rule.get("match"), where),
                    compile_regex(near, where) if near is not None else None,
                )
            )
        if not rules:
            raise Unusable(f"{sid}: no rules")
        paths, phrases = [], []
        for k, entry in enumerate(objects(raw, "allow", sid)):
            where = f"{sid} allow {k}"
            reason = entry.get("reason")
            if not isinstance(reason, str) or not reason.strip():
                raise Unusable(f"{where}: missing reason")
            if ("path" in entry) == ("phrase" in entry):
                raise Unusable(f"{where}: needs exactly one of path or phrase")
            if "path" in entry:
                if not isinstance(entry["path"], str) or not entry["path"]:
                    raise Unusable(f"{where}: expected a non-empty path glob")
                paths.append(glob_regex(entry["path"]))
            else:
                phrases.append(compile_regex(entry["phrase"], where))
        senses.append({"id": sid, "rules": rules, "paths": paths, "phrases": phrases})
    if not senses:
        raise Unusable(f"{path.name} defines no senses")
    return senses


def excluded(rel: str) -> bool:
    return (
        rel.startswith(EXCLUDED_PREFIXES)
        or Path(rel).name.startswith("CHANGELOG")
        or rel in SELF_FILES
    )


def tracked(*pathspecs: str) -> list:
    try:
        listed = subprocess.run(
            ["git", "-C", str(REPO_ROOT), "ls-files", "-z", "--", *pathspecs],
            check=True,
            capture_output=True,
        ).stdout.decode("utf-8", "surrogateescape")
    except (OSError, subprocess.CalledProcessError) as exc:
        raise Unusable(f"cannot list tracked files: {exc}") from exc
    return [p for p in listed.split("\0") if p and (REPO_ROOT / p).is_file()]


def resolve_files(args: list) -> list:
    if not args:
        return sorted(tracked())
    files = set()
    for arg in args:
        target = Path(arg).resolve()
        try:
            rel = target.relative_to(REPO_ROOT).as_posix()
        except ValueError as exc:
            raise Unusable(f"{arg}: outside the repository") from exc
        if target.is_dir():
            files.update(tracked(rel) if rel != "." else tracked())
        elif target.is_file():
            files.add(rel)
        else:
            raise Unusable(f"{arg}: no such file or directory")
    return sorted(files)


def scan(rel: str, senses: list) -> list:
    active = [s for s in senses if not any(g.match(rel) for g in s["paths"])]
    if not active:
        return []
    data = (REPO_ROOT / rel).read_bytes()
    if b"\0" in data[:8192]:
        return []
    findings = []
    lines = data.decode("utf-8", "replace").split("\n")
    for lineno, line in enumerate(lines, 1):
        for sense in active:
            hit = any(
                m.search(line) and (near is None or near.search(line))
                for m, near in sense["rules"]
            )
            if hit and not any(p.search(line) for p in sense["phrases"]):
                text = line.strip()[:TEXT_LIMIT]
                findings.append(f"{rel}:{lineno}: {sense['id']}: {text}")
    return findings


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(
        prog="check-vocabulary", description="Report uses of retired vocabulary senses."
    )
    parser.add_argument("--sense", action="append", default=[], metavar="ID")
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args(argv)
    try:
        senses = load_senses(DATA)
        known = [s["id"] for s in senses]
        unknown = [s for s in args.sense if s not in known]
        if unknown:
            raise Unusable(
                f"unknown sense {', '.join(unknown)}; known: {', '.join(known)}"
            )
        if args.sense:
            senses = [s for s in senses if s["id"] in args.sense]
        files = [f for f in resolve_files(args.paths) if not excluded(f)]
    except Unusable as exc:
        print(f"check-vocabulary: {exc}", file=sys.stderr)
        return 2
    findings = [f for rel in files for f in scan(rel, senses)]
    for finding in findings:
        print(finding)
    if findings:
        print(
            f"check-vocabulary: {len(findings)} line(s) use a retired sense; "
            f"see {DATA.name} for each replacement.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
